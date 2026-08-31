import Foundation
import RupaAgentProtocol

struct ApplicationProjectFailure: Error, Equatable, LocalizedError, Sendable {
    enum Kind: String, Equatable, Sendable {
        case applicationAuthority
        case launch
        case unsupportedProjectFormat
        case operationInProgress
        case unsavedChanges
        case newProject
        case load
        case save
        case undo
        case redo
        case agentRegistration
        case viewRecovery
    }

    let kind: Kind
    let message: String
    let didCommit: Bool
    let committedMutation: AgentCommittedMutationOutcome?

    init(
        kind: Kind,
        message: String,
        didCommit: Bool = false,
        committedMutation: AgentCommittedMutationOutcome? = nil
    ) {
        self.kind = kind
        self.message = message
        self.didCommit = didCommit
        self.committedMutation = committedMutation
    }

    var errorDescription: String? {
        message
    }
}
