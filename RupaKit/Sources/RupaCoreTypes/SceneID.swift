public struct SceneID: StableStringIdentifier {
    public static let identityName = "Scene IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
