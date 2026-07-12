import Foundation

public struct ProjectModelError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidIdentity
        case invalidReference
        case hierarchyCycle
        case duplicateRoot
        case invalidTransform
        case unsupportedSource
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
