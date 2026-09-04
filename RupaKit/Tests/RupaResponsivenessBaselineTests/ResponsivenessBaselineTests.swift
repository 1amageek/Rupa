import Foundation
import Testing

@testable import RupaResponsivenessBaseline

/// Verifies the contracts the module design owns. The measured durations are
/// host dependent and are therefore never asserted; what is asserted is that
/// the fixture is deterministic, that the plan admits the whole fixture, that
/// the duplicate preparation pass is attributable, and that a measure the
/// implementation cannot establish is reported as `notMeasured` with a reason.
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
            viewportSize: CGSize(width: 640.0, height: 480.0),
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

    @Test("The plan admits every triangle the fixture parameters predict")
    @MainActor
    func fixtureAdmission() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        #expect(report.planTriangleCount == report.predictedTriangleCount)
        #expect(report.predictedTriangleCount == Self.smallFixture.predictedTriangleCount)
        #expect(report.planTriangleCount > 0)
    }

    @Test("The duplicate validation pass is reported separately from plan construction")
    @MainActor
    func attributableDuplicatePass() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        #expect(report.samples.count == 2)
        for sample in report.samples {
            #expect(sample.planConstructionSeconds > 0.0)
            #expect(sample.validationTraversalSeconds > 0.0)
            let parts = sample.planConstructionSeconds + sample.validationTraversalSeconds
            #expect(abs(sample.preparationSeconds - parts) < 1e-9)
        }
    }

    @Test("The Canvas row states the submissions it excludes")
    @MainActor
    func honestExclusion() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        let canvas = try #require(report.rows.first { $0.row == .canvasConsumption })
        #expect(canvas.detail.contains("fill"))
        #expect(canvas.detail.contains("stroke"))
        for sample in report.samples {
            #expect(sample.fillCount == sample.triangleCount)
            #expect(sample.strokeCount == sample.triangleCount)
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

    @Test("The rows the table defines over one publication are decided by any run")
    @MainActor
    func singleRunRowsAreDecided() async throws {
        let report = try await Self.makeReport(iterationCount: 2)
        for row in [ResponsivenessAcceptanceRow.mainActorStatePublication, .cancellation] {
            let result = try #require(report.rows.first { $0.row == row })
            #expect(result.verdict != .notMeasured)
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
