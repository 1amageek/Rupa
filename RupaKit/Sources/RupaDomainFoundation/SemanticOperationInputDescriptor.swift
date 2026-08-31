public struct SemanticOperationInputDescriptor: Sendable, Equatable, Hashable {
    public let id: SemanticArgumentID
    public let type: SemanticValueType
    public let isRequired: Bool

    public init(
        id: SemanticArgumentID,
        type: SemanticValueType,
        isRequired: Bool = true
    ) {
        self.id = id
        self.type = type
        self.isRequired = isRequired
    }
}
