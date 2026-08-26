import Foundation

/// A failure observed after project authority was already published.
///
/// Callers must not retry the mutation. `commit` identifies the exact published
/// state and can be used to refresh presentation before deciding a next action.
public struct ProjectWorkspacePostCommitError: Error, LocalizedError, Sendable {
    public enum Stage: String, Sendable {
        case viewProjection
        case domainResultProjection
    }

    public let stage: Stage
    public let commit: ProjectWorkspaceCommittedMutation
    public let message: String

    public init(
        stage: Stage,
        commit: ProjectWorkspaceCommittedMutation,
        message: String
    ) {
        self.stage = stage
        self.commit = commit
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
