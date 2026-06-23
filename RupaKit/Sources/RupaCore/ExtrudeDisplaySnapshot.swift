public struct ExtrudeDisplaySnapshot: Equatable, Sendable {
    public var featureID: FeatureID
    public var profileFeatureID: FeatureID
    public var depthMeters: Double
    public var direction: ExtrudeDirection

    public init(
        featureID: FeatureID,
        profileFeatureID: FeatureID,
        depthMeters: Double,
        direction: ExtrudeDirection
    ) {
        self.featureID = featureID
        self.profileFeatureID = profileFeatureID
        self.depthMeters = depthMeters
        self.direction = direction
    }
}
