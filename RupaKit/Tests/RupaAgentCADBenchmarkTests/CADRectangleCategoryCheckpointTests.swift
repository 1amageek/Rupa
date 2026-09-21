import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADRectangleCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func allReviewedRectanglesReplaySeriallyWithCompleteCoverage() async throws {
        let expectedCases: [CADActivatedRectangleCase] = [
            .rec001, .rec002, .rec003, .rec004, .rec005, .rec006,
            .rec007, .rec008, .rec009, .rec010, .rec011, .rec012,
        ]
        #expect(CADActivatedRectangleCase.allCases == expectedCases)
        #expect(Set(expectedCases).count == 12)

        let catalog = try CADBenchmarkCatalog()
        var planes: [CADSketchPlane] = []
        var units: [CADLengthUnit] = []
        for activatedCase in expectedCases {
            let projection = try CADRectangleChallengeProjection.decode(
                catalog.challenge(for: activatedCase.caseID)
            )
            planes.append(projection.orientation)
            units.append(projection.width.unit)
            #expect(projection.width.unit == projection.height.unit)
            #expect(projection.center.unit == projection.width.unit)
        }
        #expect(planes.filter { $0 == .xy }.count == 6)
        #expect(planes.filter { $0 == .xz }.count == 3)
        #expect(planes.filter { $0 == .yz }.count == 3)
        #expect(units.filter { $0 == .millimeter }.count == 8)
        #expect(units.filter { $0 == .centimeter }.count == 1)
        #expect(units.filter { $0 == .meter }.count == 2)
        #expect(units.filter { $0 == .inch }.count == 1)

        for activatedCase in expectedCases {
            let result = try await CADRectangleCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.outcome == .realized)
            #expect(result.routeEvidence.didPublish)
            #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
            #expect(result.routeEvidence.cleanupCompleted)
            #expect(result.routeEvidence.remainingRegistrationCount == 0)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 1)
            #expect(result.telemetry.readCount >= 1)
            #expect(result.telemetry.entityCount == 4)
            #expect(result.telemetry.featureCount == 1)
            #expect(result.telemetry.bodyCount == 0)
            #expect(result.telemetry.planningWallNanoseconds > 0)
            #expect(result.telemetry.routeWallNanoseconds > 0)
            #expect(result.telemetry.oracleWallNanoseconds > 0)
            #expect(result.telemetry.totalWallNanoseconds > 0)
        }
    }
}
