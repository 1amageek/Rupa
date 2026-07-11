public extension EditorSession {
    func executeIsolatedSourceTransaction<Value>(
        commandName: String,
        commits: Bool,
        _ operation: (EditorSession) throws -> Value
    ) throws -> IsolatedSourceTransactionExecution<Value> {
        let baseGeneration = generation
        let initialSnapshot = isolatedTransactionSnapshot()
        let stagedSession = makeIsolatedTransactionSession(from: initialSnapshot)

        let value = try operation(stagedSession)
        try requireUnchangedWorkspaceState(
            in: stagedSession,
            from: initialSnapshot,
            transactionName: "Isolated source transactions"
        )
        stagedSession.commandStack.collapseUndoEntries(
            startingAt: 0,
            commandName: commandName
        )
        let proposedGeneration = stagedSession.generation
        let didMutateSource = proposedGeneration != baseGeneration
        guard stagedSession.commandStack.undoEntries.count == (didMutateSource ? 1 : 0) else {
            throw EditorError(
                code: .commandFailed,
                message: "Isolated source transaction history does not match its generation change."
            )
        }

        if commits, didMutateSource {
            publishIsolatedSourceTransaction(
                stagedSession.transactionSnapshot(),
                commandName: commandName,
                before: initialSnapshot.store.document
            )
        }

        return IsolatedSourceTransactionExecution(
            value: value,
            baseGeneration: baseGeneration,
            proposedGeneration: proposedGeneration,
            didCommit: commits && didMutateSource
        )
    }
}
