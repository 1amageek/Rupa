import RupaProject

/// The exact authority state that was published before a presentation failure.
public enum ProjectWorkspaceCommittedMutation: Sendable {
    case source(ProjectSourceCommitResult)
    case interaction(ProjectInteractionCommitResult)

    public var state: ProjectStateSnapshot {
        switch self {
        case .source(let result):
            result.state
        case .interaction(let result):
            result.state
        }
    }
}
