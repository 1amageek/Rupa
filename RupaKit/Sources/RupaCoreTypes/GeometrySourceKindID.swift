public struct GeometrySourceKindID: StableStringIdentifier {
    public static let identityName = "Geometry source kind IDs"
    public static let requiresQualifiedName = true
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
