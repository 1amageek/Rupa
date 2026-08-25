import RupaCoreTypes

public struct IsolatedSourceTransactionExecution<Value> {
    public var value: Value
    public var baseGeneration: DocumentGeneration
    public var proposedGeneration: DocumentGeneration
    public var baseTransactionRevision: DocumentTransactionRevision
    public var proposedTransactionRevision: DocumentTransactionRevision
    public var didCommit: Bool

    public init(
        value: Value,
        baseGeneration: DocumentGeneration,
        proposedGeneration: DocumentGeneration,
        baseTransactionRevision: DocumentTransactionRevision,
        proposedTransactionRevision: DocumentTransactionRevision,
        didCommit: Bool
    ) {
        self.value = value
        self.baseGeneration = baseGeneration
        self.proposedGeneration = proposedGeneration
        self.baseTransactionRevision = baseTransactionRevision
        self.proposedTransactionRevision = proposedTransactionRevision
        self.didCommit = didCommit
    }
}

extension IsolatedSourceTransactionExecution: Sendable where Value: Sendable {}
