import Foundation
import SwiftCAD

/// The profile family a cylinder body extrudes.
///
/// One outer entity names the wall the body is built to: a circle while the sweep is a full turn,
/// an arc once the sweep is partial. One inner entity, concentric with it and strictly inside it,
/// names the hollow and exists only while that hollow is positive. Two radial lines close a
/// partial sweep, running from the hollow — or from the centre when there is none — out to the
/// wall at each end of the turn. The four shapes this admits are one family rather than four,
/// so every path that reads or rewrites a cylinder's profile resolves this type instead of
/// counting entities itself, and a sector of a tube stays the same case as a solid cylinder to
/// the code that edits it.
///
/// The outer entity ID survives every edit, including the change of kind between circle and arc.
/// The inner one is minted when the hollow goes from zero to positive, kept while it stays
/// positive, and dropped when it returns to zero. The radial line IDs follow the same rule
/// against the sweep. That is the identity rule `RectangleProfileBuilder` follows for a
/// rectangle's corner arcs.
///
/// A sketch holding anything else is not a cylinder profile at all. The recognizer reports none,
/// and each caller keeps the behaviour it already has for a profile it cannot name rather than
/// guessing which of several entities is the wall. `RupaCore/DESIGN.md` owns the contract under
/// `The cylinder profile family`.
struct CylinderProfile: Sendable {
    /// One wall of the family, paired with the radius its expression resolves to.
    ///
    /// The entity is named by ID and radius rather than carried whole because the wall changes
    /// kind with the sweep: the same ID holds a `SketchCircle` at a full turn and a `SketchArc`
    /// below one, and every reader wants the radius rather than the case.
    struct Entry: Sendable {
        let id: SketchEntityID
        let radiusExpression: CADExpression
        let radius: Double
    }

    /// The two lines that close a partial sweep, named by the end of the turn each one meets.
    struct RadialEdges: Sendable {
        let start: SketchEntityID
        let end: SketchEntityID
    }

    /// The centre every entity of the family shares.
    let center: SketchPoint

    /// The wall the body is built to.
    let outer: Entry

    /// The wall the hole runs to, or `nil` when the cylinder is solid.
    let inner: Entry?

    /// Where the turn begins, in radians.
    let startAngle: Double

    /// How far the wall turns, in radians, within `(0, 2π]`.
    let sweep: Double

    /// The radial lines, or `nil` when the sweep is a full turn and the wall closes on itself.
    let radialEdges: RadialEdges?

    /// Whether the wall closes on itself, which is the case the circle profile has always been.
    var isFullTurn: Bool {
        radialEdges == nil
    }

    /// The radius of the hole, which is zero for a solid cylinder.
    ///
    /// The reading is a radius rather than a wall thickness because the property's default is zero
    /// and zero is a solid cylinder: a wall of zero thickness and a wall as thick as the radius
    /// both describe the same solid, so no monotone control could name both ends of a thickness.
    var hollowRadius: Double {
        inner?.radius ?? 0
    }
}
