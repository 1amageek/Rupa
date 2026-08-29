import RupaAgentProtocol

/// Deterministic control candidate for the activated compound path.
/// It derives one public compound action from candidate-visible text.
struct CADCompoundReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        .action(try Self.action(for: context.challenge))
    }

    static func action(for challenge: CADChallenge) throws -> CADCandidateAction {
        .compound(CADCompoundAction(members: try members(for: challenge)))
    }

    static func members(for challenge: CADChallenge) throws -> [CADCompoundMemberAction] {
        let projection = try CADCompoundChallengeProjection.decode(challenge)
        var members: [CADCompoundMemberAction] = []
        members.reserveCapacity(projection.members.count)
        for member in projection.members {
            switch member.primitive {
            case .box:
                guard let input = member.box else {
                    throw CADBenchmarkError.invalidInput(
                        caseID: challenge.id.rawValue,
                        reason: "The projected box member \(member.role) has no box payload."
                    )
                }
                members.append(CADCompoundMemberAction(
                    role: member.role,
                    name: "\(challenge.id.rawValue).\(member.role)",
                    origin: input.origin,
                    width: input.width,
                    depth: input.depth,
                    height: input.height
                ))
            case .cylinder:
                guard let input = member.cylinder else {
                    throw CADBenchmarkError.invalidInput(
                        caseID: challenge.id.rawValue,
                        reason: "The projected cylinder member \(member.role) has no cylinder payload."
                    )
                }
                members.append(CADCompoundMemberAction(
                    role: member.role,
                    name: "\(challenge.id.rawValue).\(member.role)",
                    baseCenter: input.baseCenter,
                    axis: input.axis,
                    radius: input.radius,
                    depth: input.depth
                ))
            }
        }
        return members
    }
}
