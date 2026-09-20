import Foundation

/// The arc a subdivision count divides, and the counts the canvas can draw it at.
///
/// The kernel charts circular geometry one quadrant at a time and samples every chart on its own
/// from the body's single angular tolerance, so an arc spanning several quadrants is drawn at a
/// multiple of the quadrants it covers. This type is the one owner of that relation: the resolver
/// reads the span a count divides, and the schema reads the counts the canvas can resolve.
package enum DisplayTessellationArc: Hashable, Sendable {
    /// A full turn of the circular profile the body is swept from.
    case sweptProfile
    /// One rounded corner of the all-edge round.
    case allEdgeRound

    /// The arc the binding's count divides, or `nil` when the binding names none.
    package init?(dividedBy binding: ObjectPropertyDefinition.RenderBinding?) {
        switch binding {
        case .some(.sideSegments):
            self = .sweptProfile
        case .some(.cornerSideSegments), .some(.bevelSideSegments):
            self = .allEdgeRound
        default:
            return nil
        }
    }

    /// The turning the count divides, in radians.
    package var span: Double {
        Double(quadrantCount) * .pi / 2.0
    }

    /// The number of quadrant charts the kernel samples the arc as.
    package var quadrantCount: Int {
        switch self {
        case .sweptProfile:
            4
        case .allEdgeRound:
            1
        }
    }

    /// The distance between the counts the canvas can draw the arc at.
    ///
    /// Every chart of the arc is sampled from the same angular tolerance, so the arc is drawn at
    /// the per-chart count multiplied by the number of charts.
    package var drawableCountStep: Int { quadrantCount }

    /// The fewest segments the canvas draws the arc at.
    ///
    /// A chart sampled at one segment is a chord that leaves it open, so the kernel's sampler never
    /// returns fewer than two segments for a chart.
    package var lowestDrawableCount: Int { 2 * quadrantCount }
}
