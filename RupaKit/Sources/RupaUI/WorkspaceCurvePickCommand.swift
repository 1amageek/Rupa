import RupaCore

/// A command that acts on each sketch curve the user clicks until Escape.
enum WorkspaceCurvePickCommand: Sendable, Equatable {
    /// Trim: each click removes the curve segment it lands in.
    case trim
    /// Split Segment: each click splits the curve at the clicked point.
    case splitSegment
    /// Insert Knot: each click inserts a control point into the spline at the clicked point.
    case insertKnot
    /// Bridge Curve with nothing selected: the first click places the starting point on a curve,
    /// the second the ending point, and the bridge is made.
    case bridge(first: SpatialBridgeEnd?)

    var title: String {
        switch self {
        case .trim: "Trim"
        case .splitSegment: "Split Segment"
        case .insertKnot: "Insert Knot"
        case .bridge: "Bridge Curve"
        }
    }

    var prompt: String {
        switch self {
        case .trim: "Trim: click a curve segment to remove it; Escape ends."
        case .splitSegment: "Split Segment: click a curve where it should split; Escape ends."
        case .insertKnot: "Insert Knot: click a spline where a control point should go; Escape ends."
        case .bridge(let first):
            first == nil
                ? "Bridge Curve: click the starting point on a curve; Escape ends."
                : "Bridge Curve: click the ending point on a curve; Escape ends."
        }
    }
}
