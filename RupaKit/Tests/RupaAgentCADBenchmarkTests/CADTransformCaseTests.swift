import Foundation
import RupaCore
import Testing
@testable import RupaAgentCADBenchmark

@Suite(.serialized)
struct CADTransformCaseTests {
    @Test
    func transformActionUsesExplicitDiscriminatorAndRoundTrips() throws {
        let challenge = try CADTransformPreparedCase.transform001.catalogEntry.challenge
        let projection = try CADTransformChallengeProjection.decode(challenge)
        let action = CADCandidateAction.automation(.transform(CADTransformAction(
            translation: projection.translation,
            axisPoint: projection.axisPoint,
            rotationAxis: projection.rotationAxis,
            rotation: projection.rotation
        )))
        let data = try JSONEncoder().encode(action)
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("\"kind\":\"transform\""))
        #expect(text.contains("\"axisPoint\""))
        #expect(text.contains("\"rotationAxis\""))
        #expect(try JSONDecoder().decode(CADCandidateAction.self, from: data) == action)
    }

    @Test
    func transformActivationBoundaryContainsOnlyTrn001() throws {
        #expect(CADActivatedTransformCase.allCases == [.trn001])
        do {
            _ = try CADActivatedTransformCase(caseID: "TRN-002")
            Issue.record("TRN-002 must remain outside the transform activation boundary.")
        } catch let error as CADBenchmarkError {
            #expect(error == .invalidCaseID("TRN-002"))
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func allEightPublicTransformTargetsReachProductionAndPassExactOracle() async throws {
        for preparedCase in CADTransformPreparedCase.allCases {
            let result = try await CADTransformCaseRunner(case: preparedCase).runReference()
            #expect(result.realized, "\(preparedCase.rawValue): \(result.diagnostics)")
            try result.validate()
            #expect(result.routeEvidence.didPublish)
            #expect(result.telemetry.actionCount == 1)
            #expect(result.telemetry.commandCount == 1)
            #expect(result.telemetry.readCount == expectedReadCount(for: preparedCase))
        }
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func transform001CandidateActionUsesTheProductionRoute() async throws {
        let result = try await CADTransformCaseRunner(case: .transform001)
            .run(candidate: CADTransformReferenceCandidate())

        #expect(result.caseID == "TRN-001")
        #expect(result.outcome == .realized)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence
            == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        try result.validate()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func wrongTransformActionPublishesOnceThenFailsWithoutRetry() async throws {
        let challenge = try CADTransformPreparedCase.transform001.catalogEntry.challenge
        let valid = try CADTransformReferenceCandidate().submission(for: challenge)
        let wrong = CADTransformAction(
            translation: CADPoint3D(
                x: valid.translation.x + 1,
                y: valid.translation.y,
                z: valid.translation.z,
                unit: valid.translation.unit
            ),
            axisPoint: valid.axisPoint,
            rotationAxis: valid.rotationAxis,
            rotation: valid.rotation
        )
        let result = try await CADTransformCaseRunner(case: .transform001).run(
            candidate: TransformActionCandidate(action: .automation(.transform(wrong)))
        )

        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence
            == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
        try result.validate()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func invalidTransformActionFailsBeforePublication() async throws {
        let challenge = try CADTransformPreparedCase.transform001.catalogEntry.challenge
        let valid = try CADTransformReferenceCandidate().submission(for: challenge)
        let invalid = CADTransformAction(
            translation: valid.translation,
            axisPoint: valid.axisPoint,
            rotationAxis: CADDirection3D(x: 0, y: 0, z: 0),
            rotation: valid.rotation
        )

        let result = try await CADTransformCaseRunner(case: .transform001).run(
            candidate: TransformActionCandidate(action: .automation(.transform(invalid)))
        )

        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func nonTransformCandidateActionFailsBeforePublication() async throws {
        let wrongKind = CADCandidateAction.automation(.sketch(.line(
            name: "wrong-kind",
            plane: .xy,
            start: CADPoint3D(x: 0, y: 0, z: 0),
            end: CADPoint3D(x: 1, y: 0, z: 0)
        )))

        let result = try await CADTransformCaseRunner(case: .transform001).run(
            candidate: TransformActionCandidate(action: wrongKind)
        )

        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.actionCount == 1)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func transform001CandidateDeadlineFailsBeforePublication() async throws {
        let result = try await CADTransformCaseRunner(
            case: .transform001,
            timeoutWallNanoseconds: 1
        ).run(candidate: CADTransformReferenceCandidate())

        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func transform001CandidateCancellationCannotPublishAndCleansUp() async throws {
        let task = Task { @MainActor in
            try await CADTransformCaseRunner(
                case: .transform001,
                preRouteDelayNanoseconds: 100_000_000
            ).run(candidate: CADTransformReferenceCandidate())
        }
        task.cancel()
        let result = try await task.value

        #expect(result.outcome == .cancellation)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func invalidAxisAndNonfinitePointFailBeforePublication() async throws {
        let preparedCase = CADTransformPreparedCase.transform001
        let challenge = try preparedCase.catalogEntry.challenge
        let valid = try CADTransformReferenceCandidate().submission(for: challenge)
        let invalid = CADTransformSubmission(
            translation: valid.translation,
            axisPoint: valid.axisPoint,
            rotationAxis: CADDirection3D(x: 0, y: 0, z: 0),
            rotation: valid.rotation
        )

        let result = try await CADTransformCaseRunner(case: preparedCase).run(
            submission: invalid
        )

        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.telemetry.commandCount == 0)
        #expect(result.routeEvidence.cleanupCompleted)

        let nonfinite = CADTransformSubmission(
            translation: CADPoint3D(x: .nan, y: 0, z: 0),
            axisPoint: valid.axisPoint,
            rotationAxis: valid.rotationAxis,
            rotation: valid.rotation
        )
        let nonfiniteResult = try await CADTransformCaseRunner(case: preparedCase).run(
            submission: nonfinite
        )
        #expect(nonfiniteResult.outcome == .invalidSubmission)
        #expect(nonfiniteResult.routeEvidence.didPublish == false)
        #expect(nonfiniteResult.telemetry.commandCount == 0)
        #expect(nonfiniteResult.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func wrongTransformPublishesOnceThenFailsWithoutRetry() async throws {
        let preparedCase = CADTransformPreparedCase.transform004
        let valid = try CADTransformReferenceCandidate().submission(
            for: preparedCase.catalogEntry.challenge
        )
        let wrong = CADTransformSubmission(
            translation: CADPoint3D(
                x: valid.translation.x + 1,
                y: valid.translation.y,
                z: valid.translation.z,
                unit: valid.translation.unit
            ),
            axisPoint: valid.axisPoint,
            rotationAxis: valid.rotationAxis,
            rotation: valid.rotation
        )

        let result = try await CADTransformCaseRunner(case: preparedCase).run(
            submission: wrong
        )

        #expect(result.outcome == .invalidSubmission)
        #expect(result.routeEvidence.didPublish)
        #expect(result.routeEvidence.finalPublicationSequence
            == result.routeEvidence.initialPublicationSequence + 1)
        #expect(result.telemetry.commandCount == 1)
        #expect(result.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func staleCoordinatesCannotPublish() async throws {
        let preparedCase = CADTransformPreparedCase.transform002
        let submission = try CADTransformReferenceCandidate().submission(
            for: preparedCase.catalogEntry.challenge
        )
        let result = try await CADTransformCaseRunner(case: preparedCase).runStale(
            submission: submission
        )

        #expect(result.outcome == .executionFailure)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func sharedDeadlineBoundsThePreparedRoute() async throws {
        let preparedCase = CADTransformPreparedCase.transform003
        let submission = try CADTransformReferenceCandidate().submission(
            for: preparedCase.catalogEntry.challenge
        )
        let result = try await CADTransformCaseRunner(
            case: preparedCase,
            timeoutWallNanoseconds: 1
        ).run(submission: submission)

        #expect(result.outcome == .timeout)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.cleanupCompleted)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cancellationCannotPublishAndStillCleansUp() async throws {
        let preparedCase = CADTransformPreparedCase.transform006
        let submission = try CADTransformReferenceCandidate().submission(
            for: preparedCase.catalogEntry.challenge
        )
        let task = Task { @MainActor in
            try await CADTransformCaseRunner(
                case: preparedCase,
                preRouteDelayNanoseconds: 100_000_000
            ).run(submission: submission)
        }
        task.cancel()
        let result = try await task.value

        #expect(result.outcome == .cancellation)
        #expect(result.routeEvidence.didPublish == false)
        #expect(result.routeEvidence.cleanupCompleted)
        #expect(result.routeEvidence.remainingRegistrationCount == 0)
    }

    @Test
    func categoryLocalSubmissionContainsNoPrivateOracleAuthority() throws {
        let challenge = try CADTransformPreparedCase.transform008.catalogEntry.challenge
        let submission = try CADTransformReferenceCandidate().submission(for: challenge)
        let encoded = try JSONEncoder().encode(submission)
        let text = try #require(String(data: encoded, encoding: .utf8))

        #expect(text.contains("expected") == false)
        #expect(text.contains("tolerance") == false)
        #expect(text.contains("sceneNode") == false)
        #expect(text.contains("source") == false)
    }

    private func expectedReadCount(for preparedCase: CADTransformPreparedCase) -> Int {
        switch preparedCase {
        case .transform004, .transform005:
            3
        case .transform001, .transform002, .transform003,
             .transform006, .transform007, .transform008:
            2
        }
    }
}

private struct TransformActionCandidate: CADCandidateProtocol {
    let action: CADCandidateAction

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(action)
    }
}
