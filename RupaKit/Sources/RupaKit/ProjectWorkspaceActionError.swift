import Foundation

public struct ProjectWorkspaceActionError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case snapshotUnavailable
        case actionResultMismatch
        case readRouteRequired
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
