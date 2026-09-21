import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADSphereCategoryCheckpointTests {
    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func replaysAllFiveSpheresThroughTheSemanticProductionRoute() async throws {
        let cases = CADActivatedSphereCase.allCases
        #expect(cases.map(\.rawValue) == [
            "SPH-001", "SPH-002", "SPH-003", "SPH-004", "SPH-005",
        ])

        for activatedCase in cases {
            let result = try await CADSphereCaseRunner(case: activatedCase).runReference()
            try result.validate()
            #expect(result.outcome == .realized)
            #expect(result.routeEvidence.didPublish)
            #expect(result.telemetry.featureCount == 1)
            #expect(result.telemetry.bodyCount == 1)
            #expect(result.telemetry.faceCount == 8)
            #expect(result.telemetry.edgeCount == 12)
            #expect(result.telemetry.vertexCount == 6)
            #expect(result.telemetry.analyticSurfaceCount == 8)
        }
    }
}
