public struct DesignDisplaySnapshot: Equatable, Sendable {
    public var sketches: [FeatureID: SketchDisplaySnapshot]
    public var extrudes: [FeatureID: ExtrudeDisplaySnapshot]
    public var straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot]
    public var bodies: [FeatureID: BodyDisplaySnapshot]

    public init(
        sketches: [FeatureID: SketchDisplaySnapshot] = [:],
        extrudes: [FeatureID: ExtrudeDisplaySnapshot] = [:],
        straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot] = [:],
        bodies: [FeatureID: BodyDisplaySnapshot] = [:]
    ) {
        self.sketches = sketches
        self.extrudes = extrudes
        self.straightPrismSweeps = straightPrismSweeps
        self.bodies = bodies
    }
}
