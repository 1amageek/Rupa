import Foundation
import SwiftCAD

/// The circle profile family a cylinder body extrudes.
///
/// One outer circle names the wall the body is built to. One inner circle, concentric with it and
/// strictly inside it, names the hollow and exists only while that hollow is positive. The two are
/// one family rather than two shapes, so every path that reads or rewrites a cylinder's circle
/// profile resolves this type instead of counting circle entities itself, and a tube stays the
/// same case as a solid cylinder to the code that edits it.
///
/// The outer entity ID survives every edit. The inner one is minted when the hollow goes from zero
/// to positive, kept while it stays positive, and dropped when it returns to zero, which is the
/// identity rule `RectangleProfileBuilder` follows for a rectangle's corner arcs.
///
/// A sketch holding anything else is not a cylinder profile at all. The recognizer reports none,
/// and each caller keeps the behaviour it already has for a profile it cannot name rather than
/// guessing which of several circles is the wall.
struct CylinderCircleProfile: Sendable {
    /// One circle of the family, paired with the radius its expression resolves to.
    struct Entry: Sendable {
        let id: SketchEntityID
        let circle: SketchCircle
        let radius: Double
    }

    /// The circle the wall runs to.
    let outer: Entry

    /// The circle the hole runs to, or `nil` when the cylinder is solid.
    let inner: Entry?

    /// The radius of the hole, which is zero for a solid cylinder.
    ///
    /// The reading is a radius rather than a wall thickness because the property's default is zero
    /// and zero is a solid cylinder: a wall of zero thickness and a wall as thick as the radius
    /// both describe the same solid, so no monotone control could name both ends of a thickness.
    var hollowRadius: Double {
        inner?.radius ?? 0
    }

    /// The centre both circles share.
    var center: SketchPoint {
        outer.circle.center
    }
}
