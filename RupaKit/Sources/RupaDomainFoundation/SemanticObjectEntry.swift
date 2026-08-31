public struct SemanticObjectEntry: Sendable, Equatable, Hashable {
    public let key: String
    public let value: SemanticTypedValue

    public init(key: String, value: SemanticTypedValue) {
        self.key = key
        self.value = value
    }
}
