import Foundation

public struct AgentCapabilityExecutionError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case unsupportedRoute
        case invalidPayload
        case invalidResult
        case effectMismatch
        case staleRevision
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
