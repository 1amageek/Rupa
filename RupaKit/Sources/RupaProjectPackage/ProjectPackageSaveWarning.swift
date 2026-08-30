import Foundation

/// A non-fatal condition observed after the package destination was published.
public struct ProjectPackageSaveWarning: Equatable, Sendable {
    public enum Code: String, Equatable, Sendable {
        case stagingCleanupFailed
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}
