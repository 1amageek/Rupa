import RupaCore
import SwiftCAD

/// A point the viewport resolved for a command, with where it came from.
public struct ViewportPickedPoint: Equatable, Sendable {
    public var point: Point3D
    /// The displayed occurrence whose surface the point lies on, when it came from a surface hit.
    public var occurrenceID: SceneOccurrenceID?
    /// The construction plane the point lies on, when it came from the plane.
    public var plane: SketchPlane?

    public init(point: Point3D, occurrenceID: SceneOccurrenceID? = nil, plane: SketchPlane? = nil) {
        self.point = point
        self.occurrenceID = occurrenceID
        self.plane = plane
    }
}

/// One point picked in the viewport for a command that asks for a location (an array center, a
/// placement reference): the same snap, surface and construction-plane resolution Measure uses.
public enum ViewportPointPick: Equatable, Sendable {
    case point(ViewportPickedPoint)
    /// The click resolved no point; the message says why.
    case refused(String)
}
