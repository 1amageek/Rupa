public struct IsolatedWorkspaceTransactionExecution<Value> {
    public var value: Value
    public var baseRevision: WorkspaceRevision
    public var proposedRevision: WorkspaceRevision
    public var didCommit: Bool

    public init(
        value: Value,
        baseRevision: WorkspaceRevision,
        proposedRevision: WorkspaceRevision,
        didCommit: Bool
    ) {
        self.value = value
        self.baseRevision = baseRevision
        self.proposedRevision = proposedRevision
        self.didCommit = didCommit
    }
}

extension IsolatedWorkspaceTransactionExecution: Sendable where Value: Sendable {}
