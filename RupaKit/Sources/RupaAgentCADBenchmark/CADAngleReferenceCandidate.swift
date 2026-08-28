import Foundation

/// Deterministic control candidate for an activated angle case.
/// It derives its action only from candidate-visible challenge information.
struct CADAngleReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedAngleCase(caseID: challenge.id)
        let projection = try CADAngleChallengeProjection.decode(challenge)
        guard challenge.outputRoles.map(\.name) == ["first-line", "second-line"] else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The angle challenge must declare two ordered line roles."
            )
        }
        return .automation(
            .sketch(
                .angle(
                    name: challenge.id.rawValue,
                    plane: projection.orientation,
                    firstStart: projection.intersection,
                    firstEnd: projection.firstEnd,
                    secondStart: projection.intersection,
                    secondEnd: projection.secondEnd
                )
            )
        )
    }
}
