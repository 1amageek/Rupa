import RupaCore

public extension AutomationRunner {
    func executeBatch(
        _ batch: AutomationBatch,
        in session: EditorSession
    ) throws -> [AutomationResult] {
        try executeBatchTransaction(
            batch,
            in: session,
            commits: true
        ).results
    }

    func executeBatchTransaction(
        _ batch: AutomationBatch,
        in session: EditorSession,
        commits: Bool
    ) throws -> AutomationBatchExecution {
        let effect = try batch.validatedEffect()
        try session.store.requireGeneration(batch.expectedGeneration)
        try session.requireTransactionRevision(batch.expectedTransactionRevision)
        try session.workspaceState.requireRevision(batch.expectedWorkspaceRevision)
        let prepared = PreparedAutomationBatch(batch: batch, effect: effect)

        switch effect {
        case .readOnly:
            return try executeReadOnlyBatch(prepared, in: session)
        case .sourceMutation:
            return try executeSourceBatch(prepared, in: session, commits: commits)
        case .workspaceMutation:
            return try executeWorkspaceBatch(prepared, in: session, commits: commits)
        }
    }

    private func executeReadOnlyBatch(
        _ prepared: PreparedAutomationBatch,
        in session: EditorSession
    ) throws -> AutomationBatchExecution {
        let baseGeneration = session.generation
        let transactionRevision = session.transactionRevision
        let baseWorkspaceRevision = session.workspaceState.revision
        let stage = try session.executeIsolatedReadTransaction { stagedSession in
            try AutomationStagedBatchExecutor().execute(prepared, in: stagedSession)
        }
        return AutomationBatchExecution(
            results: stage.results,
            effect: .readOnly,
            baseGeneration: baseGeneration,
            proposedGeneration: baseGeneration,
            baseTransactionRevision: transactionRevision,
            proposedTransactionRevision: transactionRevision,
            baseWorkspaceRevision: baseWorkspaceRevision,
            proposedWorkspaceRevision: baseWorkspaceRevision,
            didCommit: false,
            metrics: stage.metrics,
            finalContext: stage.finalContext
        )
    }

    private func executeSourceBatch(
        _ prepared: PreparedAutomationBatch,
        in session: EditorSession,
        commits: Bool
    ) throws -> AutomationBatchExecution {
        let batch = prepared.batch
        let workspaceRevision = session.workspaceState.revision
        let execution = try session.executeIsolatedSourceTransaction(
            commandName: "automationBatch.source",
            commits: commits,
            expectedTransactionRevision: batch.expectedTransactionRevision
        ) { stagedSession in
            let initialEvaluationPassCount = stagedSession.store.completedEvaluationPassCount
            let initialHistoryEntryCount = stagedSession.commandStack.undoEntries.count
            var stagedExecution = try stagedSession.withSourceCommandGroup(
                named: "automationBatch.source"
            ) { groupedSession in
                try AutomationStagedBatchExecutor().execute(
                    prepared,
                    in: groupedSession
                )
            }
            stagedExecution = AutomationStagedBatchExecutor().finalizingSourceMetrics(
                stagedExecution,
                initialEvaluationPassCount: initialEvaluationPassCount,
                initialHistoryEntryCount: initialHistoryEntryCount,
                in: stagedSession
            )
            return stagedExecution
        }
        return AutomationBatchExecution(
            results: execution.value.results,
            effect: .sourceMutation,
            baseGeneration: execution.baseGeneration,
            proposedGeneration: execution.proposedGeneration,
            baseTransactionRevision: execution.baseTransactionRevision,
            proposedTransactionRevision: execution.proposedTransactionRevision,
            baseWorkspaceRevision: workspaceRevision,
            proposedWorkspaceRevision: workspaceRevision,
            didCommit: execution.didCommit,
            metrics: execution.value.metrics,
            finalContext: AutomationBatchFinalContext(
                copying: execution.value.finalContext,
                transactionRevision: execution.proposedTransactionRevision
            )
        )
    }

    private func executeWorkspaceBatch(
        _ prepared: PreparedAutomationBatch,
        in session: EditorSession,
        commits: Bool
    ) throws -> AutomationBatchExecution {
        let generation = session.generation
        let transactionRevision = session.transactionRevision
        let execution = try session.executeIsolatedWorkspaceTransaction(
            commits: commits
        ) { stagedSession in
            try AutomationStagedBatchExecutor().execute(prepared, in: stagedSession)
        }
        return AutomationBatchExecution(
            results: execution.value.results,
            effect: .workspaceMutation,
            baseGeneration: generation,
            proposedGeneration: generation,
            baseTransactionRevision: transactionRevision,
            proposedTransactionRevision: transactionRevision,
            baseWorkspaceRevision: execution.baseRevision,
            proposedWorkspaceRevision: execution.proposedRevision,
            didCommit: execution.didCommit,
            metrics: execution.value.metrics,
            finalContext: execution.value.finalContext
        )
    }
}
