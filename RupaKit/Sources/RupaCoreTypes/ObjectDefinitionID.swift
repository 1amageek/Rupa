public struct ObjectDefinitionID: StableStringIdentifier {
    public static let identityName = "Object definition IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
