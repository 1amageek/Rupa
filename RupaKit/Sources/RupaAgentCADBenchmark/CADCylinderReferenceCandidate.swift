/// Deterministic control candidate for an activated cylinder case.
/// It derives its action only from candidate-visible challenge information.
struct CADCylinderReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedCylinderCase(caseID: challenge.id)
        let projection = try CADCylinderChallengeProjection.decode(challenge)
        guard challenge.outputRoles.map(\.name) == ["solid"] else {
            throw CADBenchmarkError.invalidInput(
                caseID: challenge.id.rawValue,
                reason: "The cylinder challenge must declare one solid role."
            )
        }
        return .automation(.solid(.cylinder(
            name: challenge.id.rawValue,
            baseCenter: projection.baseCenter,
            axis: projection.axis,
            radius: projection.radius,
            depth: projection.depth
        )))
    }
}
