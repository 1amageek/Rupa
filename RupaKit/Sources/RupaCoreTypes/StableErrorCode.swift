public struct StableErrorCode: StableStringIdentifier {
    public static let identityName = "Stable error codes"
    public static let requiresQualifiedName = true

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
