public extension EditorSession {
    func prepareIsolatedSourceTransaction<Value>(
        commandName: String,
        expectedTransactionRevision: DocumentTransactionRevision? = nil,
        _ operation: (EditorSession) throws -> Value
    ) throws -> PreparedEditorSourceTransaction<Value> {
        try requireTransactionRevision(expectedTransactionRevision)
        let baseTransactionRevision = transactionRevision
        let initialSnapshot = isolatedTransactionSnapshot()
        let stagedSession = makeIsolatedTransactionSession(from: initialSnapshot)

        let value = try operation(stagedSession)
        try requireUnchangedWorkspaceState(
            in: stagedSession,
            from: initialSnapshot,
            transactionName: "Isolated source transactions"
        )
        try requireOnlyPrunedSelectionState(
            in: stagedSession,
            from: initialSnapshot,
            transactionName: "Isolated source transactions"
        )
        stagedSession.commandStack.collapseUndoEntries(
            startingAt: 0,
            commandName: commandName
        )
        let proposedGeneration = stagedSession.generation
        let didMutateSource = proposedGeneration != initialSnapshot.store.document.generation
        guard stagedSession.commandStack.undoEntries.count == (didMutateSource ? 1 : 0) else {
            throw EditorError(
                code: .commandFailed,
                message: "Isolated source transaction history does not match its generation change."
            )
        }

        let proposedTransactionRevision = didMutateSource
            ? try baseTransactionRevision.advanced()
            : baseTransactionRevision
        var after = stagedSession.transactionSnapshot()
        after.transactionRevision = proposedTransactionRevision
        return PreparedEditorSourceTransaction(
            value: value,
            ownerID: transactionOwnerID,
            commandName: commandName,
            before: initialSnapshot.store.document,
            after: after,
            baseTransactionRevision: baseTransactionRevision,
            proposedTransactionRevision: proposedTransactionRevision,
            wouldMutate: didMutateSource
        )
    }

    func commitPreparedSourceTransaction<Value>(
        _ prepared: PreparedEditorSourceTransaction<Value>
    ) throws {
        try publishPreparedSourceTransaction(prepared)
    }

    func executeIsolatedSourceTransaction<Value>(
        commandName: String,
        commits: Bool,
        expectedTransactionRevision: DocumentTransactionRevision? = nil,
        _ operation: (EditorSession) throws -> Value
    ) throws -> IsolatedSourceTransactionExecution<Value> {
        let prepared = try prepareIsolatedSourceTransaction(
            commandName: commandName,
            expectedTransactionRevision: expectedTransactionRevision,
            operation
        )
        if commits {
            try commitPreparedSourceTransaction(prepared)
        }
        return IsolatedSourceTransactionExecution(
            value: prepared.value,
            baseGeneration: prepared.baseGeneration,
            proposedGeneration: prepared.proposedGeneration,
            baseTransactionRevision: prepared.baseTransactionRevision,
            proposedTransactionRevision: prepared.proposedTransactionRevision,
            didCommit: commits && prepared.wouldMutate
        )
    }
}
