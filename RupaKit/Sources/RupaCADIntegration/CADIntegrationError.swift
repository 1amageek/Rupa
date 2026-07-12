import Foundation

public struct CADIntegrationError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case unsupportedReference
        case documentMismatch
        case bodyUnavailable
        case invalidMesh
        case evaluationFailed
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
