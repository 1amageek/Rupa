public struct GeometryAttributeID: StableStringIdentifier {
    public static let identityName = "Geometry attribute IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
