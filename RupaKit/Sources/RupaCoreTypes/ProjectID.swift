public struct ProjectID: StableStringIdentifier {
    public static let identityName = "Project IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
