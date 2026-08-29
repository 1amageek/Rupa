/// Deterministic control candidate derived only from the public transform instruction.
struct CADTransformReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    /// Derives the transform action solely from the public challenge projection.
    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedTransformCase(caseID: challenge.id)
        let projection = try CADTransformChallengeProjection.decode(challenge)
        return .automation(.transform(CADTransformAction(
            translation: projection.translation,
            axisPoint: projection.axisPoint,
            rotationAxis: projection.rotationAxis,
            rotation: projection.rotation
        )))
    }

    func submission(for challenge: CADChallenge) throws -> CADTransformSubmission {
        let projection = try CADTransformChallengeProjection.decode(challenge)
        return CADTransformSubmission(
            translation: projection.translation,
            axisPoint: projection.axisPoint,
            rotationAxis: projection.rotationAxis,
            rotation: projection.rotation
        )
    }
}
