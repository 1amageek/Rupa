import Foundation

public struct ProjectControllerError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case revisionConflict
        case publicationConflict
        case sourceInvalid
        case sourceMismatch
        case transactionInvalid
        case historyUnavailable
        case productSourceFailed
        case cadSourceFailed
        case projectionFailed
        case packageFailed
        case evaluationFailed
        case snapshotUnavailable
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
