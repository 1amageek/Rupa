import Foundation
import SwiftCAD
import RupaCoreTypes

/// The single owner of what a rectangle profile is.
///
/// A rectangle profile is one family rather than two shapes: four axis-aligned lines named
/// `bottom`, `right`, `top`, and `left`, plus four corner arcs that exist only while the corner
/// radius is positive. Every path that rebuilds a rectangle profile builds it here, so a square
/// profile and a rounded one cannot disagree about the entities, the constraints, or the order
/// they are authored in.
///
/// The builder produces sketch content; recognizing an existing profile needs expression
/// resolution, so that half lives on `DesignDocument` and hands its result back as `Recognized`.
/// `RupaCore/DESIGN.md` owns the contract both halves keep.
struct RectangleProfileBuilder {

    /// The entities a rectangle profile is drawn from, named by the side or corner each one covers.
    ///
    /// The four line IDs survive every edit. The arc IDs are present exactly while the profile is
    /// rounded, so an edit that keeps the radius positive keeps the arcs it already had.
    struct EntityIDs: Equatable {
        var bottom: SketchEntityID
        var right: SketchEntityID
        var top: SketchEntityID
        var left: SketchEntityID
        var bottomRight: SketchEntityID?
        var topRight: SketchEntityID?
        var topLeft: SketchEntityID?
        var bottomLeft: SketchEntityID?

        init(
            bottom: SketchEntityID,
            right: SketchEntityID,
            top: SketchEntityID,
            left: SketchEntityID,
            bottomRight: SketchEntityID? = nil,
            topRight: SketchEntityID? = nil,
            topLeft: SketchEntityID? = nil,
            bottomLeft: SketchEntityID? = nil
        ) {
            self.bottom = bottom
            self.right = right
            self.top = top
            self.left = left
            self.bottomRight = bottomRight
            self.topRight = topRight
            self.topLeft = topLeft
            self.bottomLeft = bottomLeft
        }

        var lines: [SketchEntityID] { [bottom, right, top, left] }

        var arcs: [SketchEntityID] {
            [bottomRight, topRight, topLeft, bottomLeft].compactMap { $0 }
        }

        var isRounded: Bool { arcs.count == 4 }
    }

    /// A rectangle profile read back out of a sketch.
    struct Recognized {
        var ids: EntityIDs
        var cornerRadius: Double
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        var centerX: Double { (minX + maxX) / 2.0 }
        var centerY: Double { (minY + maxY) / 2.0 }
        var sizeX: Double { maxX - minX }
        var sizeY: Double { maxY - minY }
    }

    struct Result {
        var entities: [SketchEntityID: SketchEntity]
        var constraints: [SketchConstraint]
        /// The chain order the profile is authored in, starting at the bottom line and running
        /// counter-clockwise.
        var entityOrder: [SketchEntityID]
        var ids: EntityIDs
    }

    /// Builds the profile the size and corner radius describe about a center.
    ///
    /// A radius at or below zero builds the square profile, whose constraint set is exactly the one
    /// `DesignDocument.createRectangleSketchFromCorners` authors, so a profile that stops being
    /// rounded is indistinguishable from one that never was. A positive radius reuses the arc IDs
    /// the incoming profile carried and mints the ones it did not.
    ///
    /// The caller owns validating the radius against the size. A radius this method cannot place
    /// would produce lines of negative length rather than a diagnosable failure.
    static func build(
        centerX: Double,
        centerY: Double,
        sizeX: Double,
        sizeY: Double,
        cornerRadius: Double,
        reusing ids: EntityIDs
    ) -> Result {
        let minX = centerX - sizeX / 2.0
        let maxX = centerX + sizeX / 2.0
        let minY = centerY - sizeY / 2.0
        let maxY = centerY + sizeY / 2.0

        guard cornerRadius > 0 else {
            return build(
                bottomLeft: point(minX, minY),
                bottomRight: point(maxX, minY),
                topRight: point(maxX, maxY),
                topLeft: point(minX, maxY),
                reusing: ids
            )
        }
        return roundedProfile(
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            cornerRadius: cornerRadius,
            ids: ids
        )
    }

    /// Builds the square profile the four corners describe, keeping the expressions they carry.
    ///
    /// The dimension and direct-manipulation paths derive a corner from a named parameter, so this
    /// entry point stores what the caller supplies rather than a resolved length.
    static func build(
        bottomLeft: SketchPoint,
        bottomRight: SketchPoint,
        topRight: SketchPoint,
        topLeft: SketchPoint,
        reusing ids: EntityIDs
    ) -> Result {
        var ids = ids
        ids.bottomRight = nil
        ids.topRight = nil
        ids.topLeft = nil
        ids.bottomLeft = nil

        return Result(
            entities: [
                ids.bottom: .line(SketchLine(start: bottomLeft, end: bottomRight)),
                ids.right: .line(SketchLine(start: bottomRight, end: topRight)),
                ids.top: .line(SketchLine(start: topRight, end: topLeft)),
                ids.left: .line(SketchLine(start: topLeft, end: bottomLeft)),
            ],
            constraints: [
                .horizontal(ids.bottom),
                .vertical(ids.right),
                .horizontal(ids.top),
                .vertical(ids.left),
                .coincident(.lineEnd(ids.bottom), .lineStart(ids.right)),
                .coincident(.lineEnd(ids.right), .lineStart(ids.top)),
                .coincident(.lineEnd(ids.top), .lineStart(ids.left)),
                .coincident(.lineEnd(ids.left), .lineStart(ids.bottom)),
            ],
            entityOrder: [ids.bottom, ids.right, ids.top, ids.left],
            ids: ids
        )
    }

    private static func roundedProfile(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        cornerRadius: Double,
        ids: EntityIDs
    ) -> Result {
        var ids = ids
        let bottomRightArc = ids.bottomRight ?? SketchEntityID()
        let topRightArc = ids.topRight ?? SketchEntityID()
        let topLeftArc = ids.topLeft ?? SketchEntityID()
        let bottomLeftArc = ids.bottomLeft ?? SketchEntityID()
        ids.bottomRight = bottomRightArc
        ids.topRight = topRightArc
        ids.topLeft = topLeftArc
        ids.bottomLeft = bottomLeftArc

        let innerMinX = minX + cornerRadius
        let innerMaxX = maxX - cornerRadius
        let innerMinY = minY + cornerRadius
        let innerMaxY = maxY - cornerRadius
        let radius = CADExpression.length(cornerRadius, .meter)

        // The chain runs counter-clockwise from the bottom line and each arc turns a quarter in the
        // same direction, so the angles increase monotonically and no arc wraps past a full turn.
        let entities: [SketchEntityID: SketchEntity] = [
            ids.bottom: .line(SketchLine(start: point(innerMinX, minY), end: point(innerMaxX, minY))),
            bottomRightArc: .arc(
                SketchArc(
                    center: point(innerMaxX, innerMinY),
                    radius: radius,
                    startAngle: .angle(-Double.pi / 2.0, .radian),
                    endAngle: .angle(0.0, .radian)
                )
            ),
            ids.right: .line(SketchLine(start: point(maxX, innerMinY), end: point(maxX, innerMaxY))),
            topRightArc: .arc(
                SketchArc(
                    center: point(innerMaxX, innerMaxY),
                    radius: radius,
                    startAngle: .angle(0.0, .radian),
                    endAngle: .angle(Double.pi / 2.0, .radian)
                )
            ),
            ids.top: .line(SketchLine(start: point(innerMaxX, maxY), end: point(innerMinX, maxY))),
            topLeftArc: .arc(
                SketchArc(
                    center: point(innerMinX, innerMaxY),
                    radius: radius,
                    startAngle: .angle(Double.pi / 2.0, .radian),
                    endAngle: .angle(Double.pi, .radian)
                )
            ),
            ids.left: .line(SketchLine(start: point(minX, innerMaxY), end: point(minX, innerMinY))),
            bottomLeftArc: .arc(
                SketchArc(
                    center: point(innerMinX, innerMinY),
                    radius: radius,
                    startAngle: .angle(Double.pi, .radian),
                    endAngle: .angle(3.0 * Double.pi / 2.0, .radian)
                )
            ),
        ]

        // The coincident chain alternates line and arc endpoints. A square profile's
        // `lineEnd -> lineStart` pairing would bind two points an arc apart once the corners exist,
        // and `SketchProfileExtractor` solves any sketch that declares a constraint, so leaving the
        // stale pairing in place would collapse the shape rather than fail.
        let constraints: [SketchConstraint] = [
            .horizontal(ids.bottom),
            .vertical(ids.right),
            .horizontal(ids.top),
            .vertical(ids.left),
            .coincident(.lineEnd(ids.bottom), .arcStart(bottomRightArc)),
            .coincident(.arcEnd(bottomRightArc), .lineStart(ids.right)),
            .coincident(.lineEnd(ids.right), .arcStart(topRightArc)),
            .coincident(.arcEnd(topRightArc), .lineStart(ids.top)),
            .coincident(.lineEnd(ids.top), .arcStart(topLeftArc)),
            .coincident(.arcEnd(topLeftArc), .lineStart(ids.left)),
            .coincident(.lineEnd(ids.left), .arcStart(bottomLeftArc)),
            .coincident(.arcEnd(bottomLeftArc), .lineStart(ids.bottom)),
            .equalRadius(bottomRightArc, topRightArc),
            .equalRadius(topRightArc, topLeftArc),
            .equalRadius(topLeftArc, bottomLeftArc),
        ]

        return Result(
            entities: entities,
            constraints: constraints,
            entityOrder: [
                ids.bottom,
                bottomRightArc,
                ids.right,
                topRightArc,
                ids.top,
                topLeftArc,
                ids.left,
                bottomLeftArc,
            ],
            ids: ids
        )
    }

    private static func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(x: .length(x, .meter), y: .length(y, .meter))
    }
}
