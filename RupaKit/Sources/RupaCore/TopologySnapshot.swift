import SwiftCAD

public struct TopologySnapshot: Equatable, Sendable {
    public var counts: TopologySummaryResult.Counts
    public var entries: [TopologySummaryResult.Entry]
    /// The evaluation the entries were summarized from, so exact kernel edge and face queries
    /// answer against the same geometry. It is derived data and takes no part in equality.
    public var evaluatedDocument: EvaluatedDocument?

    public init(
        counts: TopologySummaryResult.Counts = TopologySummaryResult.Counts(),
        entries: [TopologySummaryResult.Entry] = [],
        evaluatedDocument: EvaluatedDocument? = nil
    ) {
        self.counts = counts
        self.entries = entries
        self.evaluatedDocument = evaluatedDocument
    }

    public static func == (lhs: TopologySnapshot, rhs: TopologySnapshot) -> Bool {
        lhs.counts == rhs.counts && lhs.entries == rhs.entries
    }

    public var hasGeneratedTopology: Bool {
        counts.bodyCount > 0 ||
            counts.faceCount > 0 ||
            counts.edgeCount > 0 ||
            counts.vertexCount > 0
    }
}
