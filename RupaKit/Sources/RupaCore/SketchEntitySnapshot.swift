public struct SketchEntitySnapshot: Equatable, Sendable {
    public var counts: SketchEntitySummaryResult.Counts
    public var sketches: [SketchEntitySummaryResult.SketchEntry]
    public var entries: [SketchEntitySummaryResult.EntityEntry]
    public var regions: [SketchEntitySummaryResult.RegionEntry]
    public var diagnostics: [EditorDiagnostic]

    public init(
        counts: SketchEntitySummaryResult.Counts = SketchEntitySummaryResult.Counts(),
        sketches: [SketchEntitySummaryResult.SketchEntry] = [],
        entries: [SketchEntitySummaryResult.EntityEntry] = [],
        regions: [SketchEntitySummaryResult.RegionEntry] = [],
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.counts = counts
        self.sketches = sketches
        self.entries = entries
        self.regions = regions
        self.diagnostics = diagnostics
    }
}
