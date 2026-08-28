import Testing
import RupaCore
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADBoxCaseTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001CreatesExactClosedSolidThroughProductionController() async throws {
        let result = try await CADBoxCaseRunner(case: .box001).runReference()

        try result.validate()
        #expect(result.caseID == "BOX-001")
        #expect(result.outcome == .realized)
        #expect(result.realized)
        #expect(result.candidateResult?.status == .published)
        #expect(result.candidateResult?.createdFeatureIDs.count == 2)
        #expect(result.candidateResult?.primaryFeatureID == result.candidateResult?.createdFeatureIDs.last)
        #expect(result.roleBindings?.bindings.count == 1)
        #expect(result.roleBindings?.bindings.first?.role == "solid")
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalDocumentGeneration.value == result.routeEvidence.initialDocumentGeneration.value + 1)
        #expect(result.routeEvidence.finalTransactionRevision.value == result.routeEvidence.initialTransactionRevision.value + 1)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.finalWorkspaceRevision == result.routeEvidence.initialWorkspaceRevision)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.cleanupWallNanoseconds > 0)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.telemetry.planningWallNanoseconds > 0)
        #expect(result.telemetry.routeWallNanoseconds > 0)
        #expect(result.telemetry.oracleWallNanoseconds > 0)
        #expect(result.telemetry.totalWallNanoseconds > 0)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount >= 1)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.telemetry.faceCount == 6)
        #expect(result.telemetry.edgeCount == 12)
        #expect(result.telemetry.vertexCount == 8)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001OracleRejectsWrongWidthAfterOnePublicationWithoutRetry() async throws {
        let action = boxAction(
            name: "BOX-001.wrong-width",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 12, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.telemetry.readCount == 2)
        #expect(result.telemetry.entityCount == 4)
        #expect(result.telemetry.featureCount == 2)
        #expect(result.telemetry.bodyCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("oracle mismatch") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001FailureTelemetryReadFailureIsAnOracleFailure() async throws {
        let action = boxAction(
            name: "BOX-001.wrong-width",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 12, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(
            case: .box001,
            failureSourceReader: { _ in throw BoxFailureSourceReadError.unavailable }
        ).run(action: action)

        try result.validate()
        #expect(result.outcome == .oracleFailure)
        #expect(result.telemetry.readCount == 2)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
        #expect(result.diagnostics.contains { $0.contains("failure telemetry read failed") })
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001RejectsZeroHeightBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-001.zero-height",
            origin: CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter),
            width: CADLength(value: 10, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 0, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.finalPublicationSequence == result.routeEvidence.initialPublicationSequence)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001RejectsRectangleSketchSubstituteBeforePublication() async throws {
        let action = CADCandidateAction.automation(.sketch(.rectangle(
            name: "BOX-001.rectangle-substitute",
            plane: .xy,
            center: CADPoint3D(x: 5, y: 5, z: 0, unit: .millimeter),
            width: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )))
        let result = try await CADBoxCaseRunner(case: .box001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001RejectsOffPlaneOriginBeforePublication() async throws {
        let action = boxAction(
            name: "BOX-001.off-plane",
            origin: CADPoint3D(x: 0, y: 0, z: 2, unit: .millimeter),
            width: CADLength(value: 10, unit: .millimeter),
            depth: CADLength(value: 10, unit: .millimeter),
            height: CADLength(value: 10, unit: .millimeter)
        )
        let result = try await CADBoxCaseRunner(case: .box001).run(action: action)

        try result.validate()
        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.initialPublicationSequence == result.routeEvidence.finalPublicationSequence)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func box001TimeoutIsTypedAndCleansUp() async throws {
        let result = try await CADBoxCaseRunner(
            case: .box001,
            timeoutWallNanoseconds: 1
        ).runReference()

        try result.validate()
        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.totalWallNanoseconds >= result.telemetry.timeoutWallNanoseconds)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @Test
    func box001ReferenceCandidatePreservesPublicLowerCornerAndDimensions() async throws {
        let challenge = try CADBenchmarkCatalog().challenge(for: "BOX-001")
        let decision = try await CADBoxReferenceCandidate().decide(
            for: candidateContext(challenge)
        )

        guard case .action(.automation(.solid(.box(
            let name, let origin, let width, let depth, let height
        )))) = decision else {
            Issue.record("BOX-001 candidate did not produce one solid box action.")
            return
        }
        #expect(name == "BOX-001")
        #expect(origin == CADPoint3D(x: 0, y: 0, z: 0, unit: .millimeter))
        #expect(width == CADLength(value: 10, unit: .millimeter))
        #expect(depth == CADLength(value: 10, unit: .millimeter))
        #expect(height == CADLength(value: 10, unit: .millimeter))
    }

    @Test
    func activatedBoxBoundaryContainsOnlyBOX001() throws {
        #expect(CADActivatedBoxCase.allCases == [.box001])
        for rejectedCaseID in ["BOX-002", "REC-001", "CIR-001"] {
            do {
                _ = try CADActivatedBoxCase(caseID: rejectedCaseID)
                Issue.record("\(rejectedCaseID) must remain outside the box activation boundary.")
            } catch let error as CADBenchmarkError {
                guard case .invalidCaseID(let observed) = error,
                      observed == rejectedCaseID else {
                    Issue.record("Unexpected typed error for \(rejectedCaseID): \(error)")
                    continue
                }
            }
        }
    }

    private func boxAction(
        name: String,
        origin: CADPoint3D,
        width: CADLength,
        depth: CADLength,
        height: CADLength
    ) -> CADCandidateAction {
        .automation(.solid(.box(
            name: name,
            origin: origin,
            width: width,
            depth: depth,
            height: height
        )))
    }
}

private enum BoxFailureSourceReadError: Error {
    case unavailable
}

private func candidateContext(_ challenge: CADChallenge) -> CADCandidateContext {
    CADCandidateContext(
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
}
