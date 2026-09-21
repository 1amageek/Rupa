import Foundation

/// Deterministic control candidate derived only from the public challenge.
struct CADConstraintReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedConstraintCase(caseID: challenge.id)
        let projection = try CADConstraintChallengeProjection.decode(challenge)
        guard challenge.outputRoles.map(\.name) == ["relation"] else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The public constraint challenge must declare one relation role."
            )
        }
        return .automation(.sketch(.constraint(CADConstraintAction(
            name: challenge.id.rawValue,
            plane: projection.plane,
            relation: projection.relation,
            first: projection.first,
            second: projection.second
        ))))
    }
}
