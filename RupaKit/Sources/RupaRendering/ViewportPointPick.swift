import RupaCore
import SwiftCAD

/// A point the viewport resolved for a command, with where it came from. A surface point is where
/// the displayed tessellation was hit; commands needing the exact point and normal ask Swift-CAD
/// through the face it names.
public struct ViewportPickedPoint: Equatable, Sendable {
    public var point: Point3D
    /// The displayed occurrence whose surface the point lies on, when it came from a surface hit.
    public var occurrenceID: SceneOccurrenceID?
    /// The generated CAD face of that occurrence the point lies on, when the frame drew one.
    public var faceComponentID: SelectionComponentID?
    /// The construction plane the point lies on, when it came from the plane.
    public var plane: SketchPlane?

    public init(
        point: Point3D,
        occurrenceID: SceneOccurrenceID? = nil,
        faceComponentID: SelectionComponentID? = nil,
        plane: SketchPlane? = nil
    ) {
        self.point = point
        self.occurrenceID = occurrenceID
        self.faceComponentID = faceComponentID
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
