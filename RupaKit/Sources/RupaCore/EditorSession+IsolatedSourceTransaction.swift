public extension EditorSession {
    func executeIsolatedSourceTransaction<Value>(
        commandName: String,
        commits: Bool,
        _ operation: (EditorSession) throws -> Value
    ) throws -> IsolatedSourceTransactionExecution<Value> {
        let baseGeneration = generation
        let initialSnapshot = transactionSnapshot()
        let stagedSession = makeIsolatedTransactionSession(from: initialSnapshot)
        let initialUndoCount = stagedSession.commandStack.undoEntries.count

        let value = try operation(stagedSession)
        try requireUnchangedWorkspaceState(
            in: stagedSession,
            from: initialSnapshot,
            transactionName: "Isolated source transactions"
        )
        stagedSession.commandStack.collapseUndoEntries(
            startingAt: initialUndoCount,
            commandName: commandName
        )
        let proposedGeneration = stagedSession.generation

        if commits {
            restoreTransactionSnapshot(stagedSession.transactionSnapshot())
        }

        return IsolatedSourceTransactionExecution(
            value: value,
            baseGeneration: baseGeneration,
            proposedGeneration: proposedGeneration,
            didCommit: commits && proposedGeneration != baseGeneration
        )
    }
}
