import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADCircleCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func replaysAllActivatedCirclesThroughTheProductionRoute() async throws {
        let activatedCases = Array(CADActivatedCircleCase.allCases)
        #expect(activatedCases == [
            .cir001, .cir002, .cir003, .cir004, .cir005, .cir006,
            .cir007, .cir008, .cir009, .cir010, .cir011, .cir012,
        ])
        #expect(activatedCases.count == 12)
        #expect(Set(activatedCases).count == 12)

        let catalog = try CADBenchmarkCatalog()
        var planes: [CADSketchPlane] = []
        var units: [CADLengthUnit] = []

        for activatedCase in activatedCases {
            let projection = try CADCircleChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            )
            planes.append(projection.orientation)
            units.append(projection.radius.unit)
            #expect(projection.center.unit == projection.radius.unit)

            let result = try await CADCircleCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.caseID == activatedCase.caseID)
            #expect(result.outcome == .realized)
            #expect(result.routeEvidence.didPublish)
            #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 1)
            #expect(result.telemetry.readCount >= 1)
            #expect(result.telemetry.entityCount == 1)
            #expect(result.telemetry.featureCount == 1)
            #expect(result.telemetry.bodyCount == 0)
            #expect(result.telemetry.planningWallNanoseconds > 0)
            #expect(result.telemetry.routeWallNanoseconds > 0)
            #expect(result.telemetry.oracleWallNanoseconds > 0)
            #expect(result.telemetry.totalWallNanoseconds > 0)
        }

        #expect(planes.filter { $0 == .xy }.count == 6)
        #expect(planes.filter { $0 == .xz }.count == 3)
        #expect(planes.filter { $0 == .yz }.count == 3)
        #expect(units.filter { $0 == .millimeter }.count == 8)
        #expect(units.filter { $0 == .centimeter }.count == 1)
        #expect(units.filter { $0 == .meter }.count == 2)
        #expect(units.filter { $0 == .inch }.count == 1)
    }
}
