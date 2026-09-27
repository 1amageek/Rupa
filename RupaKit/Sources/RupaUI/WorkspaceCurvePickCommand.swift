/// A command that acts on each sketch curve the user clicks until Escape.
enum WorkspaceCurvePickCommand: Sendable, Equatable {
    /// Trim: each click removes the curve segment it lands in.
    case trim
    /// Split Segment: each click splits the curve at the clicked point.
    case splitSegment

    var title: String {
        switch self {
        case .trim: "Trim"
        case .splitSegment: "Split Segment"
        }
    }

    var prompt: String {
        switch self {
        case .trim: "Trim: click a curve segment to remove it; Escape ends."
        case .splitSegment: "Split Segment: click a curve where it should split; Escape ends."
        }
    }
}
