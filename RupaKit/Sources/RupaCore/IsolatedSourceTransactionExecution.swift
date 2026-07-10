import RupaCoreTypes

public struct IsolatedSourceTransactionExecution<Value> {
    public var value: Value
    public var baseGeneration: DocumentGeneration
    public var proposedGeneration: DocumentGeneration
    public var didCommit: Bool

    public init(
        value: Value,
        baseGeneration: DocumentGeneration,
        proposedGeneration: DocumentGeneration,
        didCommit: Bool
    ) {
        self.value = value
        self.baseGeneration = baseGeneration
        self.proposedGeneration = proposedGeneration
        self.didCommit = didCommit
    }
}

extension IsolatedSourceTransactionExecution: Sendable where Value: Sendable {}
