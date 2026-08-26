import RupaCore
import RupaCoreTypes

/// Executes a prepared Automation batch against a caller-owned staged session.
public struct AutomationStagedBatchExecutor: AutomationStagedBatchExecuting, Sendable {
    private let commandRunner: AutomationRunner

    public init() {
        commandRunner = AutomationRunner(resultDetail: .commandOnly)
    }

    public func execute(
        _ prepared: PreparedAutomationBatch,
        in stagedSession: EditorSession
    ) throws -> AutomationBatchExecution {
        let batch = prepared.batch
        let effect = try batch.validatedEffect()
        guard effect == prepared.effect else {
            throw EditorError(
                code: .commandInvalid,
                message: "Prepared Automation batch effect does not match its commands."
            )
        }

        try stagedSession.store.requireGeneration(batch.expectedGeneration)
        try stagedSession.requireTransactionRevision(batch.expectedTransactionRevision)
        try stagedSession.workspaceState.requireRevision(batch.expectedWorkspaceRevision)

        let baseGeneration = stagedSession.generation
        let baseTransactionRevision = stagedSession.transactionRevision
        let baseWorkspaceRevision = stagedSession.workspaceState.revision
        let initialEvaluationCount = stagedSession.store.completedEvaluationPassCount
        let initialHistoryCount = stagedSession.commandStack.undoEntries.count

        try Task.checkCancellation()
        let commandResults = try batch.commands.map { command in
            try Task.checkCancellation()
            return try commandRunner.execute(command, in: stagedSession)
        }
        try Task.checkCancellation()
        let results = addingRequestedFinalContext(
            to: commandResults,
            commands: batch.commands,
            in: stagedSession
        )
        let evaluationPassCount = stagedSession.store.completedEvaluationPassCount
            - initialEvaluationCount
        let metrics = AutomationBatchMetrics(
            commandCount: batch.commands.count,
            evaluationPassCount: evaluationPassCount,
            historyEntryCount: stagedSession.commandStack.undoEntries.count
                - initialHistoryCount,
            richResultCount: results.filter { $0.workspaceScale != nil }.count,
            modelingEvaluation: evaluationPassCount == 0
                ? nil
                : stagedSession.store.currentModelingEvaluationMetrics
        )

        return AutomationBatchExecution(
            results: results,
            effect: effect,
            baseGeneration: baseGeneration,
            proposedGeneration: stagedSession.generation,
            baseTransactionRevision: baseTransactionRevision,
            proposedTransactionRevision: stagedSession.transactionRevision,
            baseWorkspaceRevision: baseWorkspaceRevision,
            proposedWorkspaceRevision: stagedSession.workspaceState.revision,
            didCommit: false,
            metrics: metrics,
            finalContext: AutomationBatchFinalContext(session: stagedSession)
        )
    }

    /// Finalizes metrics after an enclosing source command group has committed its
    /// deferred history entry and evaluation pass.
    public func finalizingSourceMetrics(
        _ execution: AutomationBatchExecution,
        initialEvaluationPassCount: UInt64,
        initialHistoryEntryCount: Int,
        in stagedSession: EditorSession
    ) -> AutomationBatchExecution {
        var finalized = execution
        let evaluationPassCount = stagedSession.store.completedEvaluationPassCount
            - initialEvaluationPassCount
        finalized.metrics = AutomationBatchMetrics(
            commandCount: execution.metrics.commandCount,
            evaluationPassCount: evaluationPassCount,
            historyEntryCount: stagedSession.commandStack.undoEntries.count
                - initialHistoryEntryCount,
            richResultCount: execution.metrics.richResultCount,
            modelingEvaluation: evaluationPassCount == 0
                ? nil
                : stagedSession.store.currentModelingEvaluationMetrics
        )
        finalized.finalContext = AutomationBatchFinalContext(session: stagedSession)
        return finalized
    }

    private func addingRequestedFinalContext(
        to results: [AutomationResult],
        commands: [AutomationCommand],
        in session: EditorSession
    ) -> [AutomationResult] {
        guard commands.last?.requestsWorkspaceContext == true,
              let lastIndex = results.indices.last else {
            return results
        }
        var contextualResults = results
        contextualResults[lastIndex] = commandRunner.addingWorkspaceContext(
            to: contextualResults[lastIndex],
            in: session
        )
        return contextualResults
    }
}
