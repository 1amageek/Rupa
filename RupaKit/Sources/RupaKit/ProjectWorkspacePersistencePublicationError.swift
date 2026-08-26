import Foundation
import RupaProject

/// A persistence operation committed project authority before view projection failed.
public struct ProjectWorkspacePersistencePublicationError: Error, LocalizedError, Sendable {
    public enum Operation: String, Sendable {
        case newProject
        case load
        case save
    }

    public let operation: Operation
    public let state: ProjectStateSnapshot
    public let message: String

    public init(
        operation: Operation,
        state: ProjectStateSnapshot,
        message: String
    ) {
        self.operation = operation
        self.state = state
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
