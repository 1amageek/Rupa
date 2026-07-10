public struct TopologySnapshot: Equatable, Sendable {
    public var counts: TopologySummaryResult.Counts
    public var entries: [TopologySummaryResult.Entry]

    public init(
        counts: TopologySummaryResult.Counts = TopologySummaryResult.Counts(),
        entries: [TopologySummaryResult.Entry] = []
    ) {
        self.counts = counts
        self.entries = entries
    }

    public var hasGeneratedTopology: Bool {
        counts.bodyCount > 0 ||
            counts.faceCount > 0 ||
            counts.edgeCount > 0 ||
            counts.vertexCount > 0
    }
}
