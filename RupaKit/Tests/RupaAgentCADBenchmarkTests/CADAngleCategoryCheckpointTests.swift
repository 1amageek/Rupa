import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADAngleCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func replaysAllActivatedAnglesThroughTheProductionRoute() async throws {
        let expectedCases: [CADActivatedAngleCase] = [
            .ang001, .ang002, .ang003, .ang004, .ang005, .ang006,
            .ang007, .ang008, .ang009, .ang010, .ang011, .ang012,
            .ang013, .ang014, .ang015, .ang016,
        ]
        #expect(CADActivatedAngleCase.allCases == expectedCases)
        #expect(expectedCases.count == 16)
        #expect(Set(expectedCases).count == 16)

        let catalog = try CADBenchmarkCatalog()
        var planes: [CADSketchPlane] = []
        var units: [CADLengthUnit] = []

        for activatedCase in expectedCases {
            let projection = try CADAngleChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            )
            planes.append(projection.orientation)
            units.append(projection.intersection.unit)
            #expect(projection.intersection.unit == .millimeter)
            #expect(projection.firstLength.unit == .millimeter)
            #expect(projection.secondLength.unit == .millimeter)

            let result = try await CADAngleCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.caseID == activatedCase.caseID)
            #expect(result.outcome == .realized)
            #expect(result.candidateResults.map(\.stepIndex) == [0, 1])
            #expect(result.candidateResults.allSatisfy { $0.status == .published })
            #expect(result.roleBindings?.bindings.map(\.role) == ["first-line", "second-line"])
            #expect(result.routeEvidence.didPublish)
            #expect(
                result.routeEvidence.finalPublicationSequence
                    == result.routeEvidence.initialPublicationSequence + 1
            )
            #expect(
                result.routeEvidence.finalDocumentGeneration.value
                    == result.routeEvidence.initialDocumentGeneration.value + 2
            )
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 2)
            #expect(result.telemetry.readCount >= 1)
            #expect(result.telemetry.entityCount == 2)
            #expect(result.telemetry.featureCount == 2)
            #expect(result.telemetry.bodyCount == 0)
            #expect(result.telemetry.planningWallNanoseconds > 0)
            #expect(result.telemetry.routeWallNanoseconds > 0)
            #expect(result.telemetry.oracleWallNanoseconds > 0)
            #expect(result.telemetry.totalWallNanoseconds > 0)
        }

        #expect(planes.filter { $0 == .xy }.count == 10)
        #expect(planes.filter { $0 == .xz }.count == 3)
        #expect(planes.filter { $0 == .yz }.count == 3)
        #expect(units.count == 16)
        #expect(units.filter { $0 == .millimeter }.count == 16)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func executorRetainsExactAngleRangeAfterBox005Activation() throws {
        let executor = DefaultCADActivatedCaseExecutor()
        let expectedAngles = CADActivatedAngleCase.allCases.map(\.caseID)

        #expect(executor.activatedCaseIDs.count == 57)
        #expect(Array(executor.activatedCaseIDs.prefix(52).suffix(16)) == expectedAngles)
        #expect(executor.activatedCaseIDs.suffix(5).map(\.rawValue) == ["BOX-001", "BOX-002", "BOX-003", "BOX-004", "BOX-005"])

        do {
            _ = try executor.context(for: "BOX-006")
            Issue.record("BOX-006 must remain inactive until its box case gate.")
        } catch let error as CADActivatedCaseExecutorError {
            #expect(error == .inactiveCase("BOX-006"))
        }
    }
}
