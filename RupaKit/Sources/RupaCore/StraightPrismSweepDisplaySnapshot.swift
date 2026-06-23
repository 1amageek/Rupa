public struct StraightPrismSweepDisplaySnapshot: Codable, Equatable, Sendable {
    public var featureID: FeatureID
    public var profileFeatureID: FeatureID
    public var pathFeatureID: FeatureID
    public var depthMeters: Double
    public var direction: ExtrudeDirection

    public init(
        featureID: FeatureID,
        profileFeatureID: FeatureID,
        pathFeatureID: FeatureID,
        depthMeters: Double,
        direction: ExtrudeDirection
    ) {
        self.featureID = featureID
        self.profileFeatureID = profileFeatureID
        self.pathFeatureID = pathFeatureID
        self.depthMeters = depthMeters
        self.direction = direction
    }
}
