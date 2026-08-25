import Foundation

public struct ProjectViewSnapshotError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case snapshotUnavailable
        case sourceMismatch
        case revisionMismatch
        case purposeMismatch
        case staleCADInteraction
        case missingNavigation
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
