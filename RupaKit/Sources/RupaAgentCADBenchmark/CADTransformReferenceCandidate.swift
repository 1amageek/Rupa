/// Deterministic control candidate derived only from the public transform instruction.
struct CADTransformReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    /// Derives the transform action solely from the public challenge projection.
    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        _ = try CADActivatedTransformCase(caseID: challenge.id)
        let projection = try CADTransformChallengeProjection.decode(challenge)
        let source: CADTransformSourceAction
        switch projection.source {
        case .line(let sourceProjection):
            source = .sketch(.line(
                name: "\(challenge.id.rawValue).source",
                plane: sourceProjection.orientation,
                start: sourceProjection.start,
                end: sourceProjection.end
            ))
        case .rectangle(let sourceProjection):
            source = .sketch(.rectangle(
                name: "\(challenge.id.rawValue).source",
                plane: sourceProjection.orientation,
                center: sourceProjection.center,
                width: sourceProjection.width,
                height: sourceProjection.height
            ))
        case .circle(let sourceProjection):
            source = .sketch(.circle(
                name: "\(challenge.id.rawValue).source",
                plane: sourceProjection.orientation,
                center: sourceProjection.center,
                radius: sourceProjection.radius
            ))
        case .box(let sourceProjection):
            source = .solid(.box(
                name: "\(challenge.id.rawValue).source",
                origin: sourceProjection.origin,
                width: sourceProjection.width,
                depth: sourceProjection.depth,
                height: sourceProjection.height
            ))
        case .cylinder(let sourceProjection):
            source = .solid(.cylinder(
                name: "\(challenge.id.rawValue).source",
                baseCenter: sourceProjection.baseCenter,
                axis: sourceProjection.axis,
                radius: sourceProjection.radius,
                depth: sourceProjection.depth
            ))
        }
        return .automation(.transform(CADTransformAction(
            source: source,
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
