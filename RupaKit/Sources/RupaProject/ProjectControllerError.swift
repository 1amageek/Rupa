import Foundation

public struct ProjectControllerError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case revisionConflict
        case sourceInvalid
        case mutationFailed
        case evaluationFailed
        case revisionOverflow
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
