import Foundation

public struct AgentSessionOperationResult: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Equatable, Sendable {
        case create
        case open
        case close
        case reset
        case undo
        case redo
    }

    public var operation: Operation
    public var session: WorkspaceSessionSummary
    public var commandName: String?
    public var canUndo: Bool
    public var canRedo: Bool

    public init(
        operation: Operation,
        session: WorkspaceSessionSummary,
        commandName: String? = nil,
        canUndo: Bool,
        canRedo: Bool
    ) {
        self.operation = operation
        self.session = session
        self.commandName = commandName
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}
