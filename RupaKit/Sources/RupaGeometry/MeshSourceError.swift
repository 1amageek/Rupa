import Foundation

public struct MeshSourceError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidIdentity
        case invalidBuffer
        case invalidReference
        case invalidFaceLoop
        case duplicateID
        case unsupportedOperation
        case malformedPayload
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
