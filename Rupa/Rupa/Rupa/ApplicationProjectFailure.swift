import Foundation

struct ApplicationProjectFailure: Error, Equatable, LocalizedError, Sendable {
    enum Kind: String, Equatable, Sendable {
        case launch
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

    init(kind: Kind, message: String, didCommit: Bool = false) {
        self.kind = kind
        self.message = message
        self.didCommit = didCommit
    }

    var errorDescription: String? {
        message
    }
}
