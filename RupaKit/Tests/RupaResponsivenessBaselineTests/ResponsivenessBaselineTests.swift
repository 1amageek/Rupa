import Foundation
import RupaCoreTypes
import RupaRendering
import RupaViewportScene
import Testing

@testable import RupaResponsivenessBaseline

/// Verifies the contracts the module design owns. The measured durations are
/// host dependent and are therefore never asserted; what is asserted is that
/// the fixture is deterministic, that the plan admits the whole fixture, that
/// construction is charged to readiness rather than to `MainActor`, and that a
/// measure this process cannot observe is reported as `notMeasured` with a
/// reason. No drawing contract is asserted here: the module measures none.
@Suite("Responsiveness baseline contracts")
struct ResponsivenessBaselineTests {
    /// A fixture small enough to measure inside a test while exercising the
    /// same construction path as the standard fixture.
    static let smallFixture = ResponsivenessFixture.Parameters(
        version: 1,
        name: "responsiveness-baseline-test-fixture",
        bodyCount: 2,
        segmentCount: 16,
        baseRadiusMeters: 0.030,
        radiusStepMeters: 0.002,
        lengthMeters: 0.45,
        bodySpacingMeters: 0.20
    )

    static func makeConfiguration(
        iterationCount: Int
    ) throws -> ResponsivenessBaselineRunner.Configuration {
        ResponsivenessBaselineRunner.Configuration(
            fixture: smallFixture,
            warmupCount: 1,
            iterationCount: iterationCount,
            footprintSamplingIntervalSeconds: 0.001,
            environment: try ResponsivenessEnvironment(),
            rupaKitRevision: "test-rupakit-revision",
            swiftCADRevision: "test-swift-cad-revision"
        )
    }

    @MainActor
    static func makeReport(iterationCount: Int) async throws -> ResponsivenessBaselineReport {
        let runner = try ResponsivenessBaselineRunner(
            configuration: try makeConfiguration(iterationCount: iterationCount)
        )
        return try await runner.run()
    }

    @Test("Building the fixture twice yields identical content")
    func deterministicFixture() throws {
        let first = try ResponsivenessFixture.build(Self.smallFixture)
        let second = try ResponsivenessFixture.build(Self.smallFixture)
        #expect(first.contentDigest == second.contentDigest)
        #expect(first.vertexCount == second.vertexCount)
        #expect(first.faceCount == second.faceCount)
        #expect(first.contentDigest.isEmpty == false)
    }

    @Test("The standard fixture is deterministic across builds")
    func deterministicStandardFixture() throws {
        let first = try ResponsivenessFixture.build(.standard)
        let second = try ResponsivenessFixture.build(.standard)
        #expect(first.contentDigest == second.contentDigest)
        #expect(first.vertexCount == second.vertexCount)
        #expect(first.faceCount == second.faceCount)
    }

    @Test("Twenty-four copies of the real fixture are refused before plan growth", .timeLimit(.minutes(1)))
    func repeatedRealFixtureExceedsPlanAdmission() throws {
        let fixture = try ResponsivenessFixture.build(.standard)
        var items: [UniversalViewportSceneItem] = []
        for copy in 0..<24 {
            for item in fixture.scene.items {
                items.append(UniversalViewportSceneItem(
                    id: SceneOccurrenceID(rawValue: "\(item.id.rawValue)-copy-\(copy)"),
                    definitionID: item.definitionID, displayName: item.displayName,
                    representationID: item.representationID, reference: item.reference,
                    mesh: item.mesh, worldTransform: item.worldTransform, worldBounds: item.worldBounds
                ))
            }
        }
        let scene = UniversalViewportScene(
            snapshotID: fixture.scene.snapshotID, projectID: fixture.scene.projectID,
            items: items, copyTelemetry: fixture.scene.copyTelemetry
        )
        #expect(items.count == 288)
        #expect(throws: MeshSourcePresentationRenderError.self) {
            try MeshSourcePresentationRenderPlan(scene: scene)
        }
    }

    @Test("The plan admits every triangle the fixture parameters predict")
    @MainActor
    func fixtureAdmission() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        #expect(report.planTriangleCount == report.predictedTriangleCount)
        #expect(report.predictedTriangleCount == Self.smallFixture.predictedTriangleCount)
        #expect(report.planTriangleCount > 0)
    }

    @Test("Construction is charged to readiness and never to MainActor")
    @MainActor
    func constructionIsChargedToReadinessAndNotToMainActor() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        #expect(report.samples.count == 2)
        for sample in report.samples {
            #expect(sample.constructionSeconds > 0.0)
            // The blocked interval is exactly publication. A run that charged
            // construction to MainActor could not satisfy this, so the
            // assertion fails the moment construction moves back on-actor.
            #expect(sample.mainActorBlockedSeconds == sample.publicationSeconds)
            // Readiness spans the detached construction, so it can never be the
            // shorter of the two.
            #expect(sample.readinessSeconds >= sample.constructionSeconds)
        }
    }

    @Test("Publication carries one plan that transformed each source vertex once")
    @MainActor
    func publicationIsASingleTransformingPass() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        for sample in report.samples {
            // The fixture shares vertices between triangles, so transforming
            // each source vertex once retains fewer positions than a plan that
            // transforms every triangle corner would.
            #expect(sample.positionCount > 0)
            #expect(sample.positionCount < 3 * sample.triangleCount)
            #expect(sample.retainedByteCount > 0)
            #expect(sample.workingByteCount >= sample.retainedByteCount)
        }
    }

    @Test("Every acceptance row carries a verdict and a reason")
    @MainActor
    func everyRowHasAVerdictAndReason() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        #expect(report.rows.count == ResponsivenessAcceptanceRow.allCases.count)
        for row in ResponsivenessAcceptanceRow.allCases {
            let result = try #require(report.rows.first { $0.row == row })
            #expect(result.detail.isEmpty == false)
            #expect(result.measured.isEmpty == false)
            #expect(result.threshold.isEmpty == false)
        }
    }

    @Test("A short series cannot establish acceptance for the ten-run rows")
    @MainActor
    func shortSeriesCannotAccept() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        let readiness = try #require(report.rows.first { $0.row == .planReadiness })
        #expect(readiness.verdict != .accepts)
        if readiness.verdict == .notMeasured {
            #expect(readiness.detail.contains("consecutive"))
        }
        let canvas = try #require(report.rows.first { $0.row == .canvasConsumption })
        #expect(canvas.verdict != .accepts)
    }

    @Test("A measure this process cannot observe is reported as not measured")
    @MainActor
    func unobservedMeasuresAreNotMeasured() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        let cancellation = try #require(report.rows.first { $0.row == .cancellation })
        // Reporting the preparation interval here would let a run that cancels
        // nothing accept the row.
        #expect(cancellation.verdict == .notMeasured)
        #expect(cancellation.detail.contains("No cancellation was requested"))
        let canvas = try #require(report.rows.first { $0.row == .canvasConsumption })
        // The shipped viewport draws through a mounted RealityKit frame this
        // process cannot bring up, so the row reports no duration at all
        // rather than timing an encoder the application does not run.
        #expect(canvas.verdict == .notMeasured)
        #expect(canvas.detail.contains("No drawing was measured"))
        #expect(canvas.measured == "not measured")
        let publication = try #require(
            report.rows.first { $0.row == .mainActorStatePublication }
        )
        #expect(publication.detail.contains("MainActor"))
    }

    @Test("A lower-bound row never accepts")
    @MainActor
    func lowerBoundRowsNeverAccept() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        let lowerBoundRows: [ResponsivenessAcceptanceRow] = [
            .mainActorStatePublication,
            .planRetainedBytes,
            .planWorkingBytes,
        ]
        for row in lowerBoundRows {
            let result = try #require(report.rows.first { $0.row == row })
            #expect(result.verdict != .accepts)
        }
    }

    @Test("The report round-trips through JSON unchanged")
    @MainActor
    func reportRoundTrip() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(ResponsivenessBaselineReport.self, from: data)
        #expect(decoded == report)
    }

    @Test("Derived environment inputs are flagged and supplied inputs are not")
    func environmentDerivationFlags() throws {
        let derived = try ResponsivenessEnvironment()
        #expect(derived.frameIntervalIsDerived)
        #expect(derived.minimumMemoryIsDerived)
        #expect(derived.frameIntervalSeconds == ResponsivenessEnvironment.derivedFrameIntervalSeconds)
        #expect(derived.minimumMemoryBytes == ResponsivenessEnvironment.derivedMinimumMemoryBytes)
        #expect(derived.planByteCeiling == Double(derived.minimumMemoryBytes) * 0.025)

        let supplied = try ResponsivenessEnvironment(
            frameIntervalSeconds: 1.0 / 120.0,
            minimumMemoryBytes: 16 * 1024 * 1024 * 1024
        )
        #expect(supplied.frameIntervalIsDerived == false)
        #expect(supplied.minimumMemoryIsDerived == false)
    }

    @Test("An invalid environment input is a typed failure")
    func invalidEnvironmentInputIsTyped() {
        #expect(throws: ResponsivenessBaselineError.self) {
            _ = try ResponsivenessEnvironment(frameIntervalSeconds: 0.0)
        }
        #expect(throws: ResponsivenessBaselineError.self) {
            _ = try ResponsivenessEnvironment(minimumMemoryBytes: 0)
        }
    }

    @Test("An invalid measurement request is a typed failure")
    @MainActor
    func invalidMeasurementRequestIsTyped() throws {
        var configuration = try Self.makeConfiguration(iterationCount: 1)
        configuration.iterationCount = 0
        #expect(throws: ResponsivenessBaselineError.self) {
            _ = try ResponsivenessBaselineRunner(configuration: configuration)
        }

        var missingRevision = try Self.makeConfiguration(iterationCount: 1)
        missingRevision.swiftCADRevision = ""
        #expect(throws: ResponsivenessBaselineError.self) {
            _ = try ResponsivenessBaselineRunner(configuration: missingRevision)
        }
    }
}
