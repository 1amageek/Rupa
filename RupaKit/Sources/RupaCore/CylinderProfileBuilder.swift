import Foundation
import SwiftCAD
import RupaCoreTypes

/// The single owner of what a cylinder profile is.
///
/// A cylinder profile is one family rather than four shapes: an outer wall, an optional
/// concentric inner wall, and a pair of radial lines that exist exactly while the sweep is short
/// of a full turn. Every path that rebuilds a cylinder profile builds it here, so a solid
/// cylinder, a tube, a sector, and a sector of a tube cannot disagree about the entities or the
/// order they are authored in.
///
/// A radial line runs from the hollow — or from the centre when there is none — out to the outer
/// radius at one end of the turn, so its endpoints depend on the radius, the hollow, and the
/// sweep at once. No mutator owning one of the three can write the profile correctly on its own,
/// which is why all four of them come here.
///
/// The builder produces sketch content; recognizing an existing profile needs expression
/// resolution, so that half lives on `DesignDocument` and hands its result back as
/// `CylinderProfile`. `RupaCore/DESIGN.md` owns the contract both halves keep under
/// `The cylinder profile family`.
struct CylinderProfileBuilder {

    /// One wall of the family: the expression the entity stores, and the length it resolves to.
    ///
    /// The expression is stored so a wall derived from a named parameter keeps its parameter. The
    /// resolved length places the radial line endpoints, which are plain points rather than
    /// expressions for the same reason `RectangleProfileBuilder` writes resolved corners.
    struct Wall {
        var radius: CADExpression
        var meters: Double

        init(radius: CADExpression, meters: Double) {
            self.radius = radius
            self.meters = meters
        }

        init(meters: Double) {
            self.radius = .length(meters, .meter)
            self.meters = meters
        }
    }

    /// How far the wall turns.
    ///
    /// The case rather than an angle keeps the full turn out of floating-point comparison: a
    /// mutator maps its own input to `.full` once, and every shape below one turn is a `.sector`.
    enum Turn {
        case full
        case sector(startAngle: Double, sweep: Double)
    }

    /// The entities a cylinder profile is drawn from.
    ///
    /// The outer ID survives every edit, including the change of kind between circle and arc. The
    /// inner ID is present exactly while the hollow is positive, and the radial IDs exactly while
    /// the sweep is partial.
    struct EntityIDs: Equatable {
        var outer: SketchEntityID
        var inner: SketchEntityID?
        var radialStart: SketchEntityID?
        var radialEnd: SketchEntityID?

        init(
            outer: SketchEntityID,
            inner: SketchEntityID? = nil,
            radialStart: SketchEntityID? = nil,
            radialEnd: SketchEntityID? = nil
        ) {
            self.outer = outer
            self.inner = inner
            self.radialStart = radialStart
            self.radialEnd = radialEnd
        }
    }

    struct Result {
        var entities: [SketchEntityID: SketchEntity]
        /// The order the profile is authored in: outer wall, inner wall, then the two radial lines
        /// from the start of the turn to its end.
        var entityOrder: [SketchEntityID]
        var ids: EntityIDs
    }

    /// Builds the profile the walls and the turn describe about a centre.
    ///
    /// The centre expression is stored on every circle and arc, so a profile centred on a named
    /// parameter keeps it. `centerX` and `centerY` are the same point resolved, and place the
    /// radial line endpoints.
    ///
    /// The caller owns validating the walls against each other and the sweep against the
    /// tolerance. A hollow this method cannot place would produce a wall of zero or negative
    /// thickness rather than a diagnosable failure, and a sweep whose chord falls under the
    /// tolerance would produce a profile the extractor cannot walk.
    static func build(
        center: SketchPoint,
        centerX: Double,
        centerY: Double,
        outer: Wall,
        inner: Wall?,
        turn: Turn,
        reusing ids: EntityIDs
    ) -> Result {
        var ids = ids

        switch turn {
        case .full:
            ids.radialStart = nil
            ids.radialEnd = nil
            var entities: [SketchEntityID: SketchEntity] = [
                ids.outer: .circle(SketchCircle(center: center, radius: outer.radius))
            ]
            var entityOrder: [SketchEntityID] = [ids.outer]
            if let inner {
                let innerID = ids.inner ?? SketchEntityID()
                ids.inner = innerID
                entities[innerID] = .circle(SketchCircle(center: center, radius: inner.radius))
                entityOrder.append(innerID)
            } else {
                ids.inner = nil
            }
            return Result(entities: entities, entityOrder: entityOrder, ids: ids)

        case let .sector(startAngle, sweep):
            let endAngle = startAngle + sweep
            let radialStartID = ids.radialStart ?? SketchEntityID()
            let radialEndID = ids.radialEnd ?? SketchEntityID()
            ids.radialStart = radialStartID
            ids.radialEnd = radialEndID

            var entities: [SketchEntityID: SketchEntity] = [
                ids.outer: .arc(
                    SketchArc(
                        center: center,
                        radius: outer.radius,
                        startAngle: .angle(startAngle, .radian),
                        endAngle: .angle(endAngle, .radian)
                    )
                )
            ]
            var entityOrder: [SketchEntityID] = [ids.outer]

            if let inner {
                let innerID = ids.inner ?? SketchEntityID()
                ids.inner = innerID
                entities[innerID] = .arc(
                    SketchArc(
                        center: center,
                        radius: inner.radius,
                        startAngle: .angle(startAngle, .radian),
                        endAngle: .angle(endAngle, .radian)
                    )
                )
                entityOrder.append(innerID)
            } else {
                ids.inner = nil
            }

            // The chain runs from the inner wall out at the start of the turn and back in at its
            // end, so a solid sector's two lines meet at the centre and a tube's meet the inner
            // arc's own endpoints.
            let innerStart = polar(
                centerX: centerX, centerY: centerY, radius: inner?.meters ?? 0, angle: startAngle
            )
            let innerEnd = polar(
                centerX: centerX, centerY: centerY, radius: inner?.meters ?? 0, angle: endAngle
            )
            let outerStart = polar(
                centerX: centerX, centerY: centerY, radius: outer.meters, angle: startAngle
            )
            let outerEnd = polar(
                centerX: centerX, centerY: centerY, radius: outer.meters, angle: endAngle
            )
            entities[radialStartID] = .line(SketchLine(start: innerStart, end: outerStart))
            entities[radialEndID] = .line(SketchLine(start: outerEnd, end: innerEnd))
            entityOrder.append(radialStartID)
            entityOrder.append(radialEndID)

            return Result(entities: entities, entityOrder: entityOrder, ids: ids)
        }
    }

    private static func polar(
        centerX: Double,
        centerY: Double,
        radius: Double,
        angle: Double
    ) -> SketchPoint {
        SketchPoint(
            x: .length(centerX + radius * cos(angle), .meter),
            y: .length(centerY + radius * sin(angle), .meter)
        )
    }
}
