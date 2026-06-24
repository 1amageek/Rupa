public struct DesignDisplaySnapshot: Equatable, Sendable {
    public var sketches: [FeatureID: SketchDisplaySnapshot]
    public var extrudes: [FeatureID: ExtrudeDisplaySnapshot]
    public var straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot]
    public var bodies: [FeatureID: BodyDisplaySnapshot]
    public var componentDefinitions: [ComponentDefinitionID: ComponentDefinitionDisplaySnapshot]
    public var componentInstances: [ComponentInstanceID: ComponentInstanceDisplaySnapshot]
    public var patternArrays: [PatternArraySourceID: PatternArrayDisplaySnapshot]

    public init(
        sketches: [FeatureID: SketchDisplaySnapshot] = [:],
        extrudes: [FeatureID: ExtrudeDisplaySnapshot] = [:],
        straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot] = [:],
        bodies: [FeatureID: BodyDisplaySnapshot] = [:],
        componentDefinitions: [ComponentDefinitionID: ComponentDefinitionDisplaySnapshot] = [:],
        componentInstances: [ComponentInstanceID: ComponentInstanceDisplaySnapshot] = [:],
        patternArrays: [PatternArraySourceID: PatternArrayDisplaySnapshot] = [:]
    ) {
        self.sketches = sketches
        self.extrudes = extrudes
        self.straightPrismSweeps = straightPrismSweeps
        self.bodies = bodies
        self.componentDefinitions = componentDefinitions
        self.componentInstances = componentInstances
        self.patternArrays = patternArrays
    }
}
