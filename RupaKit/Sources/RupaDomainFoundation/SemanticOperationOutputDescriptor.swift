public struct SemanticOperationOutputDescriptor: Sendable, Equatable, Hashable {
    public let id: SemanticOutputID
    public let type: SemanticValueType
    public let selector: SemanticOutputSelector

    public init(
        id: SemanticOutputID,
        type: SemanticValueType,
        selector: SemanticOutputSelector
    ) {
        self.id = id
        self.type = type
        self.selector = selector
    }
}
