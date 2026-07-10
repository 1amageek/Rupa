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
        let results = try session.executeIsolatedReadTransaction { stagedSession in
            try executeCommands(batch.commands, in: stagedSession)
        }
        return AutomationBatchExecution(
            results: results,
            effect: .readOnly,
            baseGeneration: baseGeneration,
            proposedGeneration: baseGeneration,
            baseWorkspaceRevision: baseWorkspaceRevision,
            proposedWorkspaceRevision: baseWorkspaceRevision,
            didCommit: false
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
            try executeCommands(batch.commands, in: stagedSession)
        }
        return AutomationBatchExecution(
            results: execution.value,
            effect: .sourceMutation,
            baseGeneration: execution.baseGeneration,
            proposedGeneration: execution.proposedGeneration,
            baseWorkspaceRevision: workspaceRevision,
            proposedWorkspaceRevision: workspaceRevision,
            didCommit: execution.didCommit
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
            try executeCommands(batch.commands, in: stagedSession)
        }
        return AutomationBatchExecution(
            results: execution.value,
            effect: .workspaceMutation,
            baseGeneration: generation,
            proposedGeneration: generation,
            baseWorkspaceRevision: execution.baseRevision,
            proposedWorkspaceRevision: execution.proposedRevision,
            didCommit: execution.didCommit
        )
    }

    private func executeCommands(
        _ commands: [AutomationCommand],
        in session: EditorSession
    ) throws -> [AutomationResult] {
        try commands.map { command in
            try execute(command, in: session)
        }
    }
}
