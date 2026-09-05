import CoreGraphics
import SwiftUI

/// Accumulates projected presentation polygons into one `Path` per interaction
/// visual state.
///
/// A Canvas that builds one `Path` per triangle charges one path construction,
/// one fill, and one stroke to every triangle it draws. This accumulator merges
/// every polygon of a visual state into that state's path as a closed subpath,
/// so the draw pass issues one fill and one stroke per non-empty state — three
/// of each at most, whatever the triangle count.
///
/// Merging changes what a single fill means. A `nonZero` fill of a merged path
/// cancels a clockwise subpath against a counter-clockwise one that overlaps
/// it, which would punch holes wherever a back face sits under a front face.
/// Each polygon is therefore appended with a positive screen winding, so every
/// subpath contributes the same sign and one fill covers their union.
struct ViewportPresentationBatchAccumulator {
    typealias State = MeshSourcePresentationInteractionStateResolver.State

    private var normalPath = Path()
    private var hoveredPath = Path()
    private var selectedPath = Path()

    /// Appends one convex screen polygon of three or four points. Fewer than
    /// three points bound no area and are dropped rather than drawn as a
    /// degenerate subpath.
    mutating func append(_ points: [CGPoint], state: State) {
        guard points.count >= 3 else {
            return
        }
        let isPositive = Self.signedArea(points) >= 0.0
        withPath(for: state) { path in
            if isPositive {
                path.move(to: points[0])
                for index in 1..<points.count {
                    path.addLine(to: points[index])
                }
            } else {
                path.move(to: points[points.count - 1])
                for index in stride(from: points.count - 2, through: 0, by: -1) {
                    path.addLine(to: points[index])
                }
            }
            path.closeSubpath()
        }
    }

    /// Visits every non-empty batch in draw order, so a selected surface is
    /// drawn over the hovered and normal surfaces it overlaps.
    func forEachBatch(_ visit: (State, Path) -> Void) {
        if normalPath.isEmpty == false {
            visit(.normal, normalPath)
        }
        if hoveredPath.isEmpty == false {
            visit(.hovered, hoveredPath)
        }
        if selectedPath.isEmpty == false {
            visit(.selected, selectedPath)
        }
    }

    private mutating func withPath(for state: State, _ body: (inout Path) -> Void) {
        switch state {
        case .normal:
            body(&normalPath)
        case .hovered:
            body(&hoveredPath)
        case .selected:
            body(&selectedPath)
        }
    }

    /// Twice the signed area of the projected polygon. Only its sign is read,
    /// so the factor of two is never divided out.
    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        var total: CGFloat = 0.0
        var previous = points[points.count - 1]
        for point in points {
            total += (previous.x * point.y) - (point.x * previous.y)
            previous = point
        }
        return total
    }
}
