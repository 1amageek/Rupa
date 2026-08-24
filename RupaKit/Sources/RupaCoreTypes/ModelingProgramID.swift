public struct ModelingProgramID: StableStringIdentifier {
    public static let identityName = "Modeling program IDs"
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
