import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADCylinderCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func replaysAllActivatedCylindersThroughTheProductionRoute() async throws {
        let expectedCases: [CADActivatedCylinderCase] = [
            .cylinder001, .cylinder002, .cylinder003, .cylinder004,
            .cylinder005, .cylinder006, .cylinder007, .cylinder008,
        ]
        #expect(CADActivatedCylinderCase.allCases == expectedCases)
        #expect(expectedCases.count == 8)
        #expect(Set(expectedCases).count == 8)

        let catalog = try CADBenchmarkCatalog()
        var units: [CADLengthUnit] = []
        var axes: [CADDirection3D] = []

        for activatedCase in expectedCases {
            let projection = try CADCylinderChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            )
            units.append(projection.radius.unit)
            axes.append(projection.axis)
            #expect(projection.baseCenter.unit == projection.radius.unit)
            #expect(projection.radius.unit == projection.depth.unit)

            let result = try await CADCylinderCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.caseID == activatedCase.caseID)
            #expect(result.outcome == .realized)
            #expect(result.realized)
            #expect(result.candidateResult?.status == .published)
            #expect(result.candidateResult?.createdFeatureIDs.count == 2)
            #expect(
                result.candidateResult?.primaryFeatureID
                    == result.candidateResult?.createdFeatureIDs.last
            )
            #expect(result.roleBindings?.bindings.count == 1)
            #expect(result.roleBindings?.bindings.first?.role == "solid")

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

            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 1)
            #expect(result.telemetry.readCount >= 1)
            #expect(result.telemetry.entityCount == 1)
            #expect(result.telemetry.featureCount == 2)
            #expect(result.telemetry.bodyCount == 1)
            #expect(result.telemetry.faceCount == 6)
            #expect(result.telemetry.edgeCount == 12)
            #expect(result.telemetry.vertexCount == 8)
            #expect(result.telemetry.planningWallNanoseconds > 0)
            #expect(result.telemetry.routeWallNanoseconds > 0)
            #expect(result.telemetry.oracleWallNanoseconds > 0)
            #expect(result.telemetry.totalWallNanoseconds > 0)
        }

        #expect(units.filter { $0 == .millimeter }.count == 5)
        #expect(units.filter { $0 == .centimeter }.count == 1)
        #expect(units.filter { $0 == .meter }.count == 1)
        #expect(units.filter { $0 == .inch }.count == 1)
        #expect(axes == [
            CADDirection3D(x: 0, y: 0, z: 1),
            CADDirection3D(x: 1, y: 0, z: 0),
            CADDirection3D(x: 0, y: 1, z: 0),
            CADDirection3D(x: 0, y: 0, z: -1),
            CADDirection3D(x: 0.707106781187, y: 0.707106781187, z: 0),
            CADDirection3D(x: 0, y: 0.707106781187, z: 0.707106781187),
            CADDirection3D(x: -1, y: 0, z: 0),
            CADDirection3D(x: 0.57735026919, y: 0.57735026919, z: 0.57735026919),
        ])
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorRetainsExactCylinderSuffixAndConstraintBoundary() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let expectedCylinders = CADActivatedCylinderCase.allCases.map(\.caseID)

        #expect(executor.activatedCaseIDs.count == 87)
        #expect(Array(executor.activatedCaseIDs.prefix(72).suffix(8)) == expectedCylinders)
        #expect(executor.activatedCaseIDs.last == "TRN-007")
        do {
            _ = try executor.context(for: "TRN-008")
            Issue.record("TRN-008 must remain inactive until its vertical gate.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("TRN-008"))
        }
    }
}
