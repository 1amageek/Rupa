public extension EditorSession {
    func executeIsolatedWorkspaceTransaction<Value>(
        commits: Bool,
        _ operation: (EditorSession) throws -> Value
    ) throws -> IsolatedWorkspaceTransactionExecution<Value> {
        let initialSnapshot = transactionSnapshot()
        let baseRevision = initialSnapshot.workspaceState.revision
        let stagedSession = makeIsolatedTransactionSession(from: initialSnapshot)

        let value = try operation(stagedSession)
        try requireUnchangedSourceState(
            in: stagedSession,
            from: initialSnapshot,
            transactionName: "Isolated workspace transactions"
        )
        let proposedRevision = stagedSession.workspaceState.revision

        if commits, proposedRevision != baseRevision {
            try publishWorkspaceState(stagedSession.workspaceState)
        }

        return IsolatedWorkspaceTransactionExecution(
            value: value,
            baseRevision: baseRevision,
            proposedRevision: proposedRevision,
            didCommit: commits && proposedRevision != baseRevision
        )
    }
}
