public struct SceneOccurrenceID: StableStringIdentifier {
    public static let identityName = "Scene occurrence IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
