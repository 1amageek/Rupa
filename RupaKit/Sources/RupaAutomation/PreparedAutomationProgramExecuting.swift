import RupaCore

/// Executes a prepared source program inside an already-active Core group.
public protocol PreparedAutomationProgramExecuting: Sendable {
    func execute(
        _ program: PreparedAutomationProgram,
        in stagedSession: EditorSession
    ) throws -> PreparedAutomationExecutionReceipt
}
