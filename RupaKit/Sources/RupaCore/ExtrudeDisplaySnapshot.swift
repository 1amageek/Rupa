public struct ExtrudeDisplaySnapshot: Codable, Equatable, Sendable {
    public var featureID: FeatureID
    public var profileFeatureID: FeatureID
    public var depthMeters: Double
    public var startMeters: Double
    public var endMeters: Double
    public var direction: ExtrudeDirection

    public init(
        featureID: FeatureID,
        profileFeatureID: FeatureID,
        depthMeters: Double,
        direction: ExtrudeDirection,
        startMeters: Double = 0,
        endMeters: Double? = nil
    ) {
        self.featureID = featureID
        self.profileFeatureID = profileFeatureID
        self.depthMeters = depthMeters
        self.direction = direction
        self.startMeters = startMeters
        self.endMeters = endMeters ?? depthMeters
    }
}
