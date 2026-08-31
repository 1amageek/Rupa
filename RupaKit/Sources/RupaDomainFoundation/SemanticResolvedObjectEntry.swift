public struct SemanticResolvedObjectEntry: Sendable, Equatable, Hashable {
    public let key: String
    public let value: SemanticResolvedArgument

    public init(key: String, value: SemanticResolvedArgument) {
        self.key = key
        self.value = value
    }
}
