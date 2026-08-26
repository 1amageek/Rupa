import Foundation

public struct UniversalViewportSceneError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case missingDefinition
        case projectMismatch
        case purposeMismatch
        case occurrenceMismatch
        case sourceMismatch
        case invalidIdentifier
        case sourceIdentityMismatch
    }

    public var code: Code
    public var message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
