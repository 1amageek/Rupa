import RupaProject

/// The exact mutation result and immutable view published for one action.
public enum ProjectWorkspaceActionResult: Sendable {
    case source(
        commit: ProjectSourceCommitResult,
        view: ProjectViewSnapshot
    )
    case interaction(
        commit: ProjectInteractionCommitResult,
        view: ProjectViewSnapshot
    )

    public var view: ProjectViewSnapshot {
        switch self {
        case .source(_, let view), .interaction(_, let view):
            return view
        }
    }

    public var commit: ProjectWorkspaceCommittedMutation {
        switch self {
        case .source(let commit, _):
            .source(commit)
        case .interaction(let commit, _):
            .interaction(commit)
        }
    }
}
