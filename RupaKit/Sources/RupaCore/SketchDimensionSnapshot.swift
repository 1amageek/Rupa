public struct SketchDimensionSnapshot: Equatable, Sendable {
    public var counts: SketchDimensionSummaryResult.Counts
    public var entries: [SketchDimensionSummaryResult.Entry]

    public init(
        counts: SketchDimensionSummaryResult.Counts = SketchDimensionSummaryResult.Counts(),
        entries: [SketchDimensionSummaryResult.Entry] = []
    ) {
        self.counts = counts
        self.entries = entries
    }
}
