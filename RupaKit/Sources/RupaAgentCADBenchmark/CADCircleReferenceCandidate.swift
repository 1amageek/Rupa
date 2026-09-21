import Foundation

/// Deterministic control candidate for an activated circle case.
/// It derives its action only from candidate-visible challenge information.
struct CADCircleReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedCircleCase(caseID: challenge.id)
        let projection = try CADCircleChallengeProjection.decode(challenge)
        guard challenge.outputRoles.map(\.name) == ["circle"] else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The circle challenge must declare one circle role."
            )
        }
        return .automation(
            .sketch(
                .circle(
                    name: challenge.id.rawValue,
                    plane: projection.orientation,
                    center: projection.center,
                    radius: projection.radius
                )
            )
        )
    }
}
