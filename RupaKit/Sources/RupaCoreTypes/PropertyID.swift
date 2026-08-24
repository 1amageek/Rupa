public struct PropertyID: StableStringIdentifier {
    public static let identityName = "Property IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
