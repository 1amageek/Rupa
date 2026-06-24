public struct DesignDisplaySnapshot: Equatable, Sendable {
    public var sketches: [FeatureID: SketchDisplaySnapshot]
    public var extrudes: [FeatureID: ExtrudeDisplaySnapshot]
    public var straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot]
    public var bodies: [FeatureID: BodyDisplaySnapshot]
    public var patternArrays: [PatternArraySourceID: PatternArrayDisplaySnapshot]

    public init(
        sketches: [FeatureID: SketchDisplaySnapshot] = [:],
        extrudes: [FeatureID: ExtrudeDisplaySnapshot] = [:],
        straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot] = [:],
        bodies: [FeatureID: BodyDisplaySnapshot] = [:],
        patternArrays: [PatternArraySourceID: PatternArrayDisplaySnapshot] = [:]
    ) {
        self.sketches = sketches
        self.extrudes = extrudes
        self.straightPrismSweeps = straightPrismSweeps
        self.bodies = bodies
        self.patternArrays = patternArrays
    }
}
