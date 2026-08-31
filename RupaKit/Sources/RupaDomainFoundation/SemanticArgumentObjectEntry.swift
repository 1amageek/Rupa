public struct SemanticArgumentObjectEntry: Sendable, Equatable, Hashable {
    public let key: String
    public let value: SemanticArgument

    public init(key: String, value: SemanticArgument) {
        self.key = key
        self.value = value
    }
}
