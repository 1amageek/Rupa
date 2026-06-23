public struct DesignDisplaySnapshot: Equatable, Sendable {
    public var sketches: [FeatureID: SketchDisplaySnapshot]
    public var extrudes: [FeatureID: ExtrudeDisplaySnapshot]
    public var straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot]

    public init(
        sketches: [FeatureID: SketchDisplaySnapshot] = [:],
        extrudes: [FeatureID: ExtrudeDisplaySnapshot] = [:],
        straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot] = [:]
    ) {
        self.sketches = sketches
        self.extrudes = extrudes
        self.straightPrismSweeps = straightPrismSweeps
    }
}
