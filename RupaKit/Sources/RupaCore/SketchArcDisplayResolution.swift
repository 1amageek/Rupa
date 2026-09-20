import Foundation

/// The angular resolution a sketch's own subdivision declaration draws its curves at.
///
/// A body resolves one `TessellationOptions` for its whole mesh, so every count its object declares
/// claims on it. A sketch is drawn curve by curve in its own plane, so only the counts naming arcs
/// that plane holds reach it, and the resolution the finest of them names divides every arc the
/// sketch draws. `RupaCore/DESIGN.md` owns that contract.
package enum SketchArcDisplayResolution: Hashable, Sendable {
    /// No count naming an arc this sketch holds reached it.
    case undeclared
    /// One drawn segment covers this much turning, in radians.
    case declared(radiansPerSegment: Double)

    /// The segments a full turn is drawn with where no declaration reaches the sketch.
    package static let undeclaredFullTurnSegmentCount = 48
    /// The segments an arc is drawn with where no declaration reaches the sketch.
    package static let undeclaredArcSegmentCount = 24

    /// The fewest segments a closed curve is drawn with, below which it encloses nothing.
    private static let minimumClosedSegmentCount = 3
    /// The fewest segments an open arc is drawn with, below which it is a chord.
    private static let minimumOpenSegmentCount = 2

    /// The resolution the sketch's own object declares, or `undeclared` where it declares none.
    ///
    /// A count is a candidate when its binding names an arc a sketch curve draws. A count on
    /// `bevel.segments` is not: the extrusion creates that arc, and refusing it here is why a
    /// sketch is never drawn at a resolution named for geometry it does not have.
    package init(object: ObjectDescriptor?, objectRegistry: ObjectTypeRegistry) {
        guard let object, let definition = objectRegistry.definition(for: object.typeID) else {
            self = .undeclared
            return
        }
        var finest: Double?
        for property in definition.properties where property.effect == .tessellation {
            guard case .integer(let count) = object.properties.value(
                for: property.id,
                default: property.defaultValue
            ) else { continue }
            guard let radiansPerSegment = Self.radiansPerSegment(
                count: count,
                dividing: property.renderBinding
            ) else { continue }
            finest = min(finest ?? radiansPerSegment, radiansPerSegment)
        }
        guard let finest else {
            self = .undeclared
            return
        }
        self = .declared(radiansPerSegment: finest)
    }

    /// The segments a closed circle is drawn with.
    package var fullTurnSegmentCount: Int {
        segmentCount(spanning: 2.0 * .pi, isClosed: true)
    }

    /// The segments an open arc turning through `span` radians is drawn with.
    package func arcSegmentCount(spanning span: Double) -> Int {
        segmentCount(spanning: span, isClosed: false)
    }

    /// The turning one segment covers when `count` divides the arc the binding names.
    ///
    /// A count at or below zero names no resolution, the same absence as a binding naming an arc
    /// the sketch does not hold. `ObjectPropertySet.validate(against:)` refuses such a stored count
    /// against its declared range before a document reaches the canvas, so nothing is being
    /// repaired here on the way past.
    private static func radiansPerSegment(
        count: Int,
        dividing binding: ObjectPropertyDefinition.RenderBinding?
    ) -> Double? {
        switch binding {
        case .some(.sideSegments), .some(.cornerSideSegments):
            guard count > 0, let arc = DisplayTessellationArc(dividedBy: binding) else { return nil }
            return arc.span / Double(count)
        default:
            return nil
        }
    }

    private func segmentCount(spanning span: Double, isClosed: Bool) -> Int {
        let floor = isClosed ? Self.minimumClosedSegmentCount : Self.minimumOpenSegmentCount
        switch self {
        case .undeclared:
            return isClosed ? Self.undeclaredFullTurnSegmentCount : Self.undeclaredArcSegmentCount
        case .declared(let radiansPerSegment):
            guard radiansPerSegment > 0, radiansPerSegment.isFinite, span.isFinite else {
                return floor
            }
            let fullTurn = (2.0 * .pi / radiansPerSegment).rounded(.up)
            // Turning past a full circle redraws the circle already drawn, so the resolution has
            // nothing finer to say about it than the segments one turn earns.
            let requested = (abs(span) / radiansPerSegment).rounded(.up)
            return max(Int(min(requested, fullTurn)), floor)
        }
    }
}
