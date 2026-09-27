/// A command that acts on each sketch curve the user clicks until Escape.
enum WorkspaceCurvePickCommand: Sendable, Equatable {
    /// Trim: each click removes the curve segment it lands in.
    case trim
    /// Split Segment: each click splits the curve at the clicked point.
    case splitSegment
    /// Insert Knot: each click inserts a control point into the spline at the clicked point.
    case insertKnot

    var title: String {
        switch self {
        case .trim: "Trim"
        case .splitSegment: "Split Segment"
        case .insertKnot: "Insert Knot"
        }
    }

    var prompt: String {
        switch self {
        case .trim: "Trim: click a curve segment to remove it; Escape ends."
        case .splitSegment: "Split Segment: click a curve where it should split; Escape ends."
        case .insertKnot: "Insert Knot: click a spline where a control point should go; Escape ends."
        }
    }
}
