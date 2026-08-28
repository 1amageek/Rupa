import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADRectangleCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec001CreatesExactClosedRectangleThroughProductionController() async throws {
        let result = try await CADRectangleCaseRunner(case: .rec001).runReference()

        try result.validate()
        #expect(result.caseID == "REC-001")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 1)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.first)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 1)
        #expect(result.telemetry.bodyCount == 0)
        print(
            "REC-001 telemetry: planning=\(result.telemetry.planningWallNanoseconds)ns "
                + "route=\(result.telemetry.routeWallNanoseconds)ns "
                + "oracle=\(result.telemetry.oracleWallNanoseconds)ns "
                + "total=\(result.telemetry.totalWallNanoseconds)ns"
        )
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec001OracleRejectsSameAreaSwappedDimensionsWithoutRetry() async throws {
        let swapped = CADCandidateAction.automation(.sketch(.rectangle(
            name: "REC-001.swapped",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 20, unit: .millimeter),
            height: CADLength(value: 40, unit: .millimeter)
        )))

        let result = try await CADRectangleCaseRunner(case: .rec001).run(action: swapped)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec001RejectsOffPlaneCenterBeforePublication() async throws {
        let offPlane = CADCandidateAction.automation(.sketch(.rectangle(
            name: "REC-001.off-plane",
            plane: .xy,
            center: CADPoint3D(x: 0, y: 0, z: 2, unit: .millimeter),
            width: CADLength(value: 40, unit: .millimeter),
            height: CADLength(value: 20, unit: .millimeter)
        )))

        let result = try await CADRectangleCaseRunner(case: .rec001).run(action: offPlane)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.routeEvidence.initialPublicationSequence == result.routeEvidence.finalPublicationSequence)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func rec001TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADRectangleCaseRunner(
            case: .rec001,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(!result.routeEvidence.didPublish)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test
    func rec001ReferenceCandidateUsesOnlyChallengeProjection() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "REC-001")
        let context = CADCandidateContext(
            challenge: challenge,
            capabilities: CADCapabilitySnapshot(
                version: "test.v1",
                statuses: [CADCapabilityStatus(
                    id: challenge.requiredCapability.id,
                    version: challenge.requiredCapability.version,
                    available: true
                )]
            ),
            remainingRounds: challenge.budget.maximumRounds,
            remainingActions: challenge.budget.maximumActions
        )
        let decision = try await CADRectangleReferenceCandidate().decide(for: context)

        guard case .action(.automation(.sketch(.rectangle(
            _, let plane, let center, let width, let height
        )))) = decision else {
            Issue.record("REC-001 candidate did not produce one rectangle action.")
            return
        }
        #expect(plane == .xy)
        #expect(center == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 40, unit: .millimeter))
        #expect(height == CADLength(value: 20, unit: .millimeter))
    }

    @Test
    func activatedRectangleBoundaryContainsOnlyRec001() throws {
        #expect(CADActivatedRectangleCase.allCases == [.rec001])

        for rejectedCaseID in ["REC-002", "LIN-001"] {
            do {
                _ = try CADActivatedRectangleCase(caseID: rejectedCaseID)
                Issue.record("\(rejectedCaseID) must remain outside the rectangle activation boundary.")
            } catch let error as CADBenchmarkError {
                guard case .invalidCaseID(let observed) = error,
                      observed == rejectedCaseID else {
                    Issue.record("Unexpected typed error for \(rejectedCaseID): \(error)")
                    continue
                }
            }
        }
    }
}
