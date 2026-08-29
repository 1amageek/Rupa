import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADBoxCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func replaysAllActivatedBoxesThroughTheProductionRoute() async throws {
        let expectedCases: [CADActivatedBoxCase] = [
            .box001, .box002, .box003, .box004, .box005, .box006,
            .box007, .box008, .box009, .box010, .box011, .box012,
        ]
        #expect(CADActivatedBoxCase.allCases == expectedCases)
        #expect(expectedCases.count == 12)
        #expect(Set(expectedCases).count == 12)

        let catalog = try CADBenchmarkCatalog()
        var units: [CADLengthUnit] = []
        var cubeCount = 0
        var nonCubeCount = 0

        for activatedCase in expectedCases {
            let projection = try CADBoxChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            )
            units.append(projection.width.unit)
            #expect(projection.origin.unit == projection.width.unit)
            #expect(projection.width.unit == projection.depth.unit)
            #expect(projection.depth.unit == projection.height.unit)

            if projection.width.meters == projection.depth.meters,
               projection.depth.meters == projection.height.meters {
                cubeCount += 1
            } else {
                nonCubeCount += 1
            }

            let result = try await CADBoxCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.caseID == activatedCase.caseID)
            #expect(result.outcome == .realized)
            #expect(result.realized)
            #expect(result.candidateResult?.status == .published)
            #expect(result.candidateResult?.createdFeatureIDs.count == 2)
            #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.last)
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
            #expect(result.telemetry.entityCount == 4)
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

        #expect(units.filter { $0 == .millimeter }.count == 9)
        #expect(units.filter { $0 == .meter }.count == 2)
        #expect(units.filter { $0 == .inch }.count == 1)
        #expect(cubeCount == 5)
        #expect(nonCubeCount == 7)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorRetainsHistoricalBoxPrefixAfterCylinderActivation() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let expectedBoxes = CADActivatedBoxCase.allCases.map(\.caseID)

        #expect(executor.activatedCaseIDs.count == 96)
        #expect(Array(executor.activatedCaseIDs.prefix(64).suffix(expectedBoxes.count)) == expectedBoxes)
        #expect(executor.activatedCaseIDs.prefix(65).last == "CYL-001")
        #expect(executor.activatedCaseIDs.prefix(66).last == "CYL-002")
        #expect(executor.activatedCaseIDs.prefix(67).last == "CYL-003")
        #expect(executor.activatedCaseIDs.prefix(68).last == "CYL-004")
        #expect(executor.activatedCaseIDs.prefix(69).last == "CYL-005")
        #expect(executor.activatedCaseIDs.prefix(70).last == "CYL-006")
        #expect(executor.activatedCaseIDs.prefix(71).last == "CYL-007")
        #expect(executor.activatedCaseIDs.prefix(72).last == "CYL-008")
        #expect(executor.activatedCaseIDs.prefix(88).last == "TRN-008")
        #expect(executor.activatedCaseIDs.prefix(89).last == "CMP-001")
        #expect(executor.activatedCaseIDs.prefix(90).last == "CMP-002")
        #expect(executor.activatedCaseIDs.prefix(91).last == "CMP-003")
        #expect(executor.activatedCaseIDs.prefix(92).last == "CMP-004")
        #expect(executor.activatedCaseIDs.prefix(93).last == "CMP-005")
        #expect(executor.activatedCaseIDs.prefix(94).last == "CMP-006")
        #expect(executor.activatedCaseIDs.prefix(95).last == "CMP-007")
        #expect(executor.activatedCaseIDs.last == "SPH-001")
    }
}
