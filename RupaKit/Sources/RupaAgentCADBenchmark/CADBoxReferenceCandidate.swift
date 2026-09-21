import Foundation

/// Deterministic control candidate for the activated box case.
/// It derives its action only from candidate-visible challenge information.
struct CADBoxReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedBoxCase(caseID: challenge.id)
        let projection = try CADBoxChallengeProjection.decode(challenge)
        guard challenge.outputRoles.map(\.name) == ["solid"] else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The box challenge must declare one solid role."
            )
        }
        return .automation(
            .solid(
                .box(
                    name: challenge.id.rawValue,
                    origin: projection.origin,
                    width: projection.width,
                    depth: projection.depth,
                    height: projection.height
                )
            )
        )
    }
}
