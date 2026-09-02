import Foundation

/// Deterministic control candidate derived only from the public sphere challenge.
struct CADSphereReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedSphereCase(caseID: challenge.id)
        let projection = try CADSphereChallengeProjection.decode(challenge)
        guard challenge.outputRoles.map(\.name) == ["sphere"] else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The sphere challenge must declare one sphere role."
            )
        }
        return .automation(.solid(.sphere(
            name: challenge.id.rawValue,
            center: projection.center,
            radius: projection.radius
        )))
    }
}
