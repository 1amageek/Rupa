public extension EditorSession {
    func prepareUndo(
        expectedTransactionRevision: DocumentTransactionRevision? = nil
    ) throws -> PreparedEditorHistoryTransaction {
        try prepareHistoryTransaction(
            expectedTransactionRevision: expectedTransactionRevision
        ) { stagedSession in
            try stagedSession.commandStack.undo(in: stagedSession.store)
        }
    }

    func prepareRedo(
        expectedTransactionRevision: DocumentTransactionRevision? = nil
    ) throws -> PreparedEditorHistoryTransaction {
        try prepareHistoryTransaction(
            expectedTransactionRevision: expectedTransactionRevision
        ) { stagedSession in
            try stagedSession.commandStack.redo(in: stagedSession.store)
        }
    }

    func commitPreparedHistoryTransaction(
        _ prepared: PreparedEditorHistoryTransaction
    ) throws {
        guard prepared.ownerID == transactionOwnerID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Prepared history transactions belong to the session that staged them."
            )
        }
        try requireTransactionRevision(prepared.baseTransactionRevision)
        try store.requireGeneration(prepared.baseGeneration)
        guard selection == prepared.baseSelection else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection changed after the history transaction was staged."
            )
        }
        guard workspaceState.revision == prepared.baseWorkspaceRevision else {
            throw EditorError(
                code: .workspaceRevisionMismatch,
                message: "Workspace state changed after the history transaction was staged."
            )
        }
        guard commandStack.snapshot().mutationToken
            === prepared.baseHistoryMutationToken else {
            throw EditorError(
                code: .commandInvalid,
                message: "Command history changed after the history transaction was staged."
            )
        }
        restoreTransactionSnapshot(prepared.after)
    }

    private func prepareHistoryTransaction(
        expectedTransactionRevision: DocumentTransactionRevision?,
        _ operation: (EditorSession) throws -> CommandExecutionResult
    ) throws -> PreparedEditorHistoryTransaction {
        try requireTransactionRevision(expectedTransactionRevision)
        let baseGeneration = generation
        let baseTransactionRevision = transactionRevision
        let initialSnapshot = transactionSnapshot()
        let stagedSession = makeIsolatedTransactionSession(from: initialSnapshot)
        let result = try operation(stagedSession)
        guard stagedSession.generation != baseGeneration,
              result.didMutate,
              result.generation == stagedSession.generation else {
            throw EditorError(
                code: .commandFailed,
                message: "History staging did not produce one evaluated source mutation."
            )
        }
        guard stagedSession.evaluatedGeneration == stagedSession.generation else {
            throw EditorError(
                code: .evaluationFailed,
                message: "History staging did not evaluate the proposed document generation."
            )
        }
        switch stagedSession.evaluationStatus {
        case .valid:
            break
        case .failed(let message):
            throw EditorError(code: .evaluationFailed, message: message)
        case .notEvaluated:
            throw EditorError(
                code: .evaluationFailed,
                message: "History staging did not produce a document evaluation."
            )
        }
        let proposedTransactionRevision = try baseTransactionRevision.advanced()
        var after = stagedSession.transactionSnapshot()
        after.transactionRevision = proposedTransactionRevision
        return PreparedEditorHistoryTransaction(
            result: result,
            ownerID: transactionOwnerID,
            baseGeneration: baseGeneration,
            baseTransactionRevision: baseTransactionRevision,
            baseSelection: initialSnapshot.selection,
            baseWorkspaceRevision: initialSnapshot.workspaceState.revision,
            baseHistoryMutationToken: initialSnapshot.commandStack.mutationToken,
            after: after
        )
    }
}
