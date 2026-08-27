import Foundation

/// Typed failure for the exact-snapshot CAD Make Editable use case.
public struct ProjectMakeEditableError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case cancelled
        case invalidRequest
        case projectMismatch
        case documentLifetimeMismatch
        case documentGenerationMismatch
        case transactionRevisionMismatch
        case publicationSequenceMismatch
        case workspaceRevisionMismatch
        case sourceMissing
        case sourceIdentityMismatch
        case representationMissing
        case representationMismatch
        case duplicateIdentity
        case nonCADModelingSource
        case invalidSource
        case resultMismatch
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
