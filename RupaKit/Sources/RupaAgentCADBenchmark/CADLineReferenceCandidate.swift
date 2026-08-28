import Foundation

/// Deterministic control candidate used to exercise the production Agent
/// route for an activated line case.
///
/// The candidate is deliberately limited to the public challenge projection.
/// It has no access to the private catalog, expected geometry, or oracle.
struct CADLineReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    /// Derives the deterministic control action solely from public challenge
    /// text and typed public values.
    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedLineCase(caseID: challenge.id)
        let projection = try CADLineChallengeProjection.decode(challenge)
        guard challenge.outputRoles.map(\.name) == ["segment"] else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public line challenge must declare one segment role."
            )
        }
        return .automation(
            .sketch(
                .line(
                    name: challenge.id.rawValue,
                    plane: projection.orientation,
                    start: projection.start,
                    end: projection.end
                )
            )
        )
    }
}
