import Foundation

/// Deterministic control candidate for an activated rectangle case.
/// It derives its action only from candidate-visible challenge information.
struct CADRectangleReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedRectangleCase(caseID: challenge.id)
        let projection = try CADRectangleChallengeProjection.decode(challenge)
        guard challenge.outputRoles.map(\.name) == ["rectangle"] else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The rectangle challenge must declare one rectangle role."
            )
        }
        return .automation(
            .sketch(
                .rectangle(
                    name: challenge.id.rawValue,
                    plane: projection.orientation,
                    center: projection.center,
                    width: projection.width,
                    height: projection.height
                )
            )
        )
    }
}
