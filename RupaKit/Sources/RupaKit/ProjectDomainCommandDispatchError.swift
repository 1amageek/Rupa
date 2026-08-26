import Foundation

/// A domain command cannot be lowered from the supplied immutable project view.
public struct ProjectDomainCommandDispatchError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case generationMismatch
        case projectMismatch
        case transactionRevisionMismatch
        case publicationSequenceMismatch
        case workspaceRevisionMismatch
        case actionRouteMismatch
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
