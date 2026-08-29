import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADTransformCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func replaysAllActivatedTransformsWithExactCoverageAndLifecycle() async throws {
        let expectedCases: [CADActivatedTransformCase] = [
            .trn001, .trn002, .trn003, .trn004,
            .trn005, .trn006, .trn007, .trn008,
        ]
        #expect(CADActivatedTransformCase.allCases == expectedCases)
        #expect(expectedCases.count == 8)
        #expect(Set(expectedCases).count == 8)
        let executor = DefaultCADActivatedCaseExecutor()
        #expect(executor.activatedCaseIDs.count == 100)
        #expect(Set(executor.activatedCaseIDs) == Set(try CADBenchmarkCatalog().caseIDs))
        #expect(executor.activatedCaseIDs.prefix(89).last == "CMP-001")
        #expect(executor.activatedCaseIDs.prefix(90).last == "CMP-002")
        #expect(executor.activatedCaseIDs.prefix(91).last == "CMP-003")
        #expect(executor.activatedCaseIDs.prefix(92).last == "CMP-004")
        #expect(executor.activatedCaseIDs.prefix(93).last == "CMP-005")
        #expect(executor.activatedCaseIDs.prefix(94).last == "CMP-006")
        #expect(executor.activatedCaseIDs.prefix(95).last == "CMP-007")
        #expect(executor.activatedCaseIDs.prefix(96).last == "SPH-001")
        #expect(executor.activatedCaseIDs.prefix(97).last == "SPH-002")
        #expect(executor.activatedCaseIDs.prefix(98).last == "SPH-003")
        #expect(executor.activatedCaseIDs.prefix(99).last == "SPH-004")
        #expect(executor.activatedCaseIDs.last == "SPH-005")
        #expect(Array(executor.activatedCaseIDs.prefix(88).suffix(expectedCases.count))
            == expectedCases.map(\.caseID))

        let catalog = try CADBenchmarkCatalog()
        var projections: [CADTransformChallengeProjection] = []
        for activatedCase in expectedCases {
            projections.append(try CADTransformChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            ))
        }

        let sourceKinds = projections.map { projection in
            switch projection.source {
            case .line:
                "line"
            case .rectangle:
                "rectangle"
            case .circle:
                "circle"
            case .box:
                "box"
            case .cylinder:
                "cylinder"
            }
        }
        #expect(sourceKinds == [
            "line", "rectangle", "circle", "box",
            "cylinder", "line", "rectangle", "circle",
        ])
        #expect(sourceKinds.filter { $0 == "line" }.count == 2)
        #expect(sourceKinds.filter { $0 == "rectangle" }.count == 2)
        #expect(sourceKinds.filter { $0 == "circle" }.count == 2)
        #expect(sourceKinds.filter { $0 == "box" }.count == 1)
        #expect(sourceKinds.filter { $0 == "cylinder" }.count == 1)
        #expect(sourceKinds.filter { ["line", "rectangle", "circle"].contains($0) }.count == 6)
        #expect(sourceKinds.filter { ["box", "cylinder"].contains($0) }.count == 2)

        let sketchPlanes = projections.compactMap { projection -> CADSketchPlane? in
            switch projection.source {
            case .line(let source):
                source.orientation
            case .rectangle(let source):
                source.orientation
            case .circle(let source):
                source.orientation
            case .box, .cylinder:
                nil
            }
        }
        #expect(sketchPlanes == [.xy, .xy, .xy, .xy, .yz, .xy])
        #expect(sketchPlanes.filter { $0 == .xy }.count == 5)
        #expect(sketchPlanes.filter { $0 == .yz }.count == 1)

        #expect(projections.map(\.axisPoint) == [
            CADPoint3D(x: 50, y: 0, z: 0),
            CADPoint3D(x: 0, y: 0, z: 0),
            CADPoint3D(x: 0, y: 0, z: 0),
            CADPoint3D(x: 10, y: 15, z: 20),
            CADPoint3D(x: 0, y: 0, z: 20),
            CADPoint3D(x: 0, y: 0, z: 0),
            CADPoint3D(x: 0, y: 0, z: 0),
            CADPoint3D(x: 25, y: -25, z: 0),
        ])
        #expect(projections.filter {
            $0.axisPoint == CADPoint3D(x: 0, y: 0, z: 0)
        }.count == 4)
        #expect(projections.filter {
            $0.axisPoint != CADPoint3D(x: 0, y: 0, z: 0)
        }.count == 4)

        #expect(projections.map(\.rotationAxis) == [
            CADDirection3D(x: 0, y: 0, z: 1),
            CADDirection3D(x: 0, y: 0, z: 1),
            CADDirection3D(x: 1, y: 0, z: 0),
            CADDirection3D(x: 0, y: 0, z: 1),
            CADDirection3D(x: 0, y: 1, z: 0),
            CADDirection3D(x: 1, y: 0, z: 0),
            CADDirection3D(x: 0, y: 0, z: 1),
            CADDirection3D(
                x: 0.57735026919,
                y: 0.57735026919,
                z: 0.57735026919
            ),
        ])
        #expect(projections.filter {
            $0.rotationAxis == CADDirection3D(x: 0, y: 0, z: 1)
        }.count == 4)
        #expect(projections.filter {
            $0.rotationAxis == CADDirection3D(x: 1, y: 0, z: 0)
        }.count == 2)
        #expect(projections.filter {
            $0.rotationAxis == CADDirection3D(x: 0, y: 1, z: 0)
        }.count == 1)
        #expect(projections.filter {
            $0.rotationAxis == CADDirection3D(
                x: 0.57735026919,
                y: 0.57735026919,
                z: 0.57735026919
            )
        }.count == 1)

        #expect(projections.map(\.rotation.value) == [30, 45, 90, 15, 30, 120, 180, 60])
        #expect(projections.allSatisfy { $0.rotation.unit == .degree })
        #expect(projections.filter {
            $0.translation == CADPoint3D(x: 0, y: 0, z: 0)
        }.count == 1)
        #expect(projections.filter {
            $0.translation != CADPoint3D(x: 0, y: 0, z: 0)
        }.count == 7)

        let expectedReads = [2, 2, 2, 3, 3, 2, 2, 2]
        let expectedFeatures = [1, 1, 1, 2, 2, 1, 1, 1]
        let expectedBodies = [0, 0, 0, 1, 1, 0, 0, 0]
        var readCounts: [Int] = []
        var featureCounts: [Int] = []
        var sceneNodeCounts: [Int] = []
        var bodyCounts: [Int] = []

        for activatedCase in expectedCases {
            let result = try await CADTransformCaseRunner(
                case: activatedCase.preparedCase
            ).runReference()
            try result.validate()

            #expect(result.caseID == activatedCase.caseID)
            #expect(result.outcome == .realized)
            #expect(result.routeEvidence.didPublish)
            #expect(
                result.routeEvidence.finalPublicationSequence
                    == result.routeEvidence.initialPublicationSequence + 1
            )
            #expect(
                result.routeEvidence.finalDocumentGeneration.value
                    == result.routeEvidence.initialDocumentGeneration.value + 1
            )
            #expect(
                result.routeEvidence.finalTransactionRevision.value
                    == result.routeEvidence.initialTransactionRevision.value + 1
            )
            #expect(
                result.routeEvidence.finalWorkspaceRevision
                    == result.routeEvidence.initialWorkspaceRevision
            )
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)

            readCounts.append(result.telemetry.readCount)
            featureCounts.append(result.telemetry.featureCount)
            sceneNodeCounts.append(result.telemetry.sceneNodeCount)
            bodyCounts.append(result.telemetry.bodyCount)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 1)
            #expect(result.telemetry.planningWallNanoseconds > 0)
            #expect(result.telemetry.routeWallNanoseconds > 0)
            #expect(result.telemetry.oracleWallNanoseconds > 0)
            #expect(result.telemetry.totalWallNanoseconds > 0)
        }

        #expect(readCounts == expectedReads)
        #expect(featureCounts == expectedFeatures)
        #expect(sceneNodeCounts == expectedFeatures)
        #expect(bodyCounts == expectedBodies)
    }
}
