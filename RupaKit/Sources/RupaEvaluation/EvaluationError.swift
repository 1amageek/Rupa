import Foundation

public struct EvaluationError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case providerNotRegistered
        case sourceUnavailable
        case hierarchyCycle
        case invalidProject
        case invalidResult
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
