import RupaProject

/// Fixed-shape postpublication alternative reserved before staging.
public struct ProjectCommittedFailurePlan: Sendable, Equatable {
    public init() {}

    public func result(
        code: ProjectSemanticProgramCommittedFailure.Code,
        state: ProjectStateSnapshot
    ) -> ProjectSemanticProgramCommittedFailure {
        ProjectSemanticProgramCommittedFailure(
            code: code,
            authority: state.authorityCoordinate
        )
    }
}
