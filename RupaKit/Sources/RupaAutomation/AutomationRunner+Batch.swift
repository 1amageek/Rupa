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
        try session.workspaceState.requireRevision(batch.expectedWorkspaceRevision)

        switch effect {
        case .readOnly:
            return try executeReadOnlyBatch(batch, in: session)
        case .sourceMutation:
            return try executeSourceBatch(batch, in: session, commits: commits)
        case .workspaceMutation:
            return try executeWorkspaceBatch(batch, in: session, commits: commits)
        }
    }

    private func executeReadOnlyBatch(
        _ batch: AutomationBatch,
        in session: EditorSession
    ) throws -> AutomationBatchExecution {
        let baseGeneration = session.generation
        let baseWorkspaceRevision = session.workspaceState.revision
        let stage = try session.executeIsolatedReadTransaction { stagedSession in
            try executeStage(batch.commands, in: stagedSession) {
                try executeCommandsWithRequestedContext(batch.commands, in: stagedSession)
            }
        }
        return AutomationBatchExecution(
            results: stage.results,
            effect: .readOnly,
            baseGeneration: baseGeneration,
            proposedGeneration: baseGeneration,
            baseWorkspaceRevision: baseWorkspaceRevision,
            proposedWorkspaceRevision: baseWorkspaceRevision,
            didCommit: false,
            metrics: stage.metrics
        )
    }

    private func executeSourceBatch(
        _ batch: AutomationBatch,
        in session: EditorSession,
        commits: Bool
    ) throws -> AutomationBatchExecution {
        let workspaceRevision = session.workspaceState.revision
        let execution = try session.executeIsolatedSourceTransaction(
            commandName: "automationBatch.source",
            commits: commits
        ) { stagedSession in
            try executeStage(batch.commands, in: stagedSession) {
                let results = try stagedSession.withSourceCommandGroup(
                    named: "automationBatch.source"
                ) { groupedSession in
                    try executeCommandOnlyResults(batch.commands, in: groupedSession)
                }
                return addingRequestedFinalContext(
                    to: results,
                    commands: batch.commands,
                    in: stagedSession
                )
            }
        }
        return AutomationBatchExecution(
            results: execution.value.results,
            effect: .sourceMutation,
            baseGeneration: execution.baseGeneration,
            proposedGeneration: execution.proposedGeneration,
            baseWorkspaceRevision: workspaceRevision,
            proposedWorkspaceRevision: workspaceRevision,
            didCommit: execution.didCommit,
            metrics: execution.value.metrics
        )
    }

    private func executeWorkspaceBatch(
        _ batch: AutomationBatch,
        in session: EditorSession,
        commits: Bool
    ) throws -> AutomationBatchExecution {
        let generation = session.generation
        let execution = try session.executeIsolatedWorkspaceTransaction(
            commits: commits
        ) { stagedSession in
            try executeStage(batch.commands, in: stagedSession) {
                try executeCommandsWithRequestedContext(batch.commands, in: stagedSession)
            }
        }
        return AutomationBatchExecution(
            results: execution.value.results,
            effect: .workspaceMutation,
            baseGeneration: generation,
            proposedGeneration: generation,
            baseWorkspaceRevision: execution.baseRevision,
            proposedWorkspaceRevision: execution.proposedRevision,
            didCommit: execution.didCommit,
            metrics: execution.value.metrics
        )
    }

    private func executeCommandsWithRequestedContext(
        _ commands: [AutomationCommand],
        in session: EditorSession
    ) throws -> [AutomationResult] {
        addingRequestedFinalContext(
            to: try executeCommandOnlyResults(commands, in: session),
            commands: commands,
            in: session
        )
    }

    private func executeCommandOnlyResults(
        _ commands: [AutomationCommand],
        in session: EditorSession
    ) throws -> [AutomationResult] {
        let commandRunner = AutomationRunner(resultDetail: .commandOnly)
        return try commands.map { command in
            try commandRunner.execute(command, in: session)
        }
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
        contextualResults[lastIndex] = addingWorkspaceContext(
            to: contextualResults[lastIndex],
            in: session
        )
        return contextualResults
    }

    private func executeStage(
        _ commands: [AutomationCommand],
        in session: EditorSession,
        _ operation: () throws -> [AutomationResult]
    ) throws -> AutomationBatchStageExecution {
        let initialEvaluationCount = session.store.completedEvaluationPassCount
        let initialHistoryCount = session.commandStack.undoEntries.count
        let results = try operation()
        let evaluationPassCount = session.store.completedEvaluationPassCount
            - initialEvaluationCount
        return AutomationBatchStageExecution(
            results: results,
            metrics: AutomationBatchMetrics(
                commandCount: commands.count,
                evaluationPassCount: evaluationPassCount,
                historyEntryCount: session.commandStack.undoEntries.count
                    - initialHistoryCount,
                richResultCount: results.filter { $0.workspaceScale != nil }.count,
                modelingEvaluation: evaluationPassCount == 0
                    ? nil
                    : session.store.currentModelingEvaluationMetrics
            )
        )
    }
}

private struct AutomationBatchStageExecution {
    var results: [AutomationResult]
    var metrics: AutomationBatchMetrics
}
