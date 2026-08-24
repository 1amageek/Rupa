public struct AssetID: StableStringIdentifier {
    public static let identityName = "Asset IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
