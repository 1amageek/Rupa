import RupaCore

/// Executes a prepared Automation batch inside a caller-owned staged session.
public protocol AutomationStagedBatchExecuting: Sendable {
    func execute(
        _ prepared: PreparedAutomationBatch,
        in stagedSession: EditorSession
    ) throws -> AutomationBatchExecution

    func finalizingSourceMetrics(
        _ execution: AutomationBatchExecution,
        initialEvaluationPassCount: UInt64,
        initialHistoryEntryCount: Int,
        in stagedSession: EditorSession
    ) -> AutomationBatchExecution
}
