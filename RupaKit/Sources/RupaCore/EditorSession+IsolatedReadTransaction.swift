public extension EditorSession {
    func executeIsolatedReadTransaction<Value>(
        _ operation: (EditorSession) throws -> Value
    ) throws -> Value {
        let initialSnapshot = transactionSnapshot()
        let stagedSession = makeIsolatedTransactionSession(from: initialSnapshot)

        let value = try operation(stagedSession)
        try requireUnchangedSourceState(
            in: stagedSession,
            from: initialSnapshot,
            transactionName: "Isolated read transactions"
        )
        try requireUnchangedWorkspaceState(
            in: stagedSession,
            from: initialSnapshot,
            transactionName: "Isolated read transactions"
        )
        return value
    }
}
