import Foundation

public struct ProjectMeshEditError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case cancelled
        case projectMismatch
        case documentLifetimeMismatch
        case documentGenerationMismatch
        case transactionRevisionMismatch
        case publicationSequenceMismatch
        case workspaceRevisionMismatch
        case sourceMissing
        case sourceIdentityMismatch
        case invalidPlan
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
