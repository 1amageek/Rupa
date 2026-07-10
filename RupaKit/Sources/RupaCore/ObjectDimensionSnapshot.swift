public struct ObjectDimensionSnapshot: Equatable, Sendable {
    public var counts: ObjectDimensionSummaryResult.Counts
    public var entries: [ObjectDimensionSummaryResult.Entry]

    public init(
        counts: ObjectDimensionSummaryResult.Counts = ObjectDimensionSummaryResult.Counts(),
        entries: [ObjectDimensionSummaryResult.Entry] = []
    ) {
        self.counts = counts
        self.entries = entries
    }
}
