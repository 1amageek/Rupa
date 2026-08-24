public struct GeometryOutputID: StableStringIdentifier {
    public static let identityName = "Geometry output IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
