import RupaCoreTypes
public struct DesignDisplaySnapshotResult: Codable, Equatable, Sendable {
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var workspaceScale: WorkspaceScaleSnapshot
    public var sketches: [SketchDisplaySnapshot]
    public var extrudes: [ExtrudeDisplaySnapshot]
    public var straightPrismSweeps: [StraightPrismSweepDisplaySnapshot]
    public var bodies: [BodyDisplaySnapshot]
    public var componentDefinitions: [ComponentDefinitionDisplaySnapshot]
    public var componentInstances: [ComponentInstanceDisplaySnapshot]
    public var patternArrays: [PatternArrayDisplaySnapshot]

    public init(
        generation: DocumentGeneration,
        dirty: Bool,
        workspaceScale: WorkspaceScaleSnapshot = WorkspaceScaleSnapshot(ruler: .standard(for: .millimeter)),
        sketches: [SketchDisplaySnapshot],
        extrudes: [ExtrudeDisplaySnapshot],
        straightPrismSweeps: [StraightPrismSweepDisplaySnapshot],
        bodies: [BodyDisplaySnapshot],
        componentDefinitions: [ComponentDefinitionDisplaySnapshot] = [],
        componentInstances: [ComponentInstanceDisplaySnapshot] = [],
        patternArrays: [PatternArrayDisplaySnapshot] = []
    ) {
        self.generation = generation
        self.dirty = dirty
        self.workspaceScale = workspaceScale
        self.sketches = sketches
        self.extrudes = extrudes
        self.straightPrismSweeps = straightPrismSweeps
        self.bodies = bodies
        self.componentDefinitions = componentDefinitions
        self.componentInstances = componentInstances
        self.patternArrays = patternArrays
    }
}
