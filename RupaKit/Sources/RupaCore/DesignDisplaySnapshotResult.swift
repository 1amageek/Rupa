public struct DesignDisplaySnapshotResult: Codable, Equatable, Sendable {
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var sketches: [SketchDisplaySnapshot]
    public var extrudes: [ExtrudeDisplaySnapshot]
    public var straightPrismSweeps: [StraightPrismSweepDisplaySnapshot]
    public var bodies: [BodyDisplaySnapshot]

    public init(
        generation: DocumentGeneration,
        dirty: Bool,
        sketches: [SketchDisplaySnapshot],
        extrudes: [ExtrudeDisplaySnapshot],
        straightPrismSweeps: [StraightPrismSweepDisplaySnapshot],
        bodies: [BodyDisplaySnapshot]
    ) {
        self.generation = generation
        self.dirty = dirty
        self.sketches = sketches
        self.extrudes = extrudes
        self.straightPrismSweeps = straightPrismSweeps
        self.bodies = bodies
    }
}
