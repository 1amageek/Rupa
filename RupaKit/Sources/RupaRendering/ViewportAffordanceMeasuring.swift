import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// The three questions an affordance drag is allowed to ask the frame that
/// drew its handle.
///
/// Each requirement is already solved by the mounted frame, so a drag never
/// rebuilds a projection of its own to measure with. There is deliberately no
/// point-projection requirement: the legacy measurement offset a model point
/// by one unit, projected the offset point and the centre, and read the screen
/// vector between them. That probe is a metre-long ray inside a body whose own
/// extent is centimetres, and the standard perspective camera stands a
/// comparable centimetre distance from it, so the probe point fell behind the
/// eye and every quantity derived from it resolved to nothing. Answering the
/// question the action actually asks removes the class of defect rather than
/// one instance of it.
///
/// A refusal is typed and scoped to the axis or plane actually asked for, so a
/// camera that cannot answer along one world axis still answers along the two
/// it draws.
@MainActor
protocol ViewportAffordanceMeasuring {
    /// The signed metres travelled along `axisDirection` between two screen
    /// points, measured on the axis through `axisOrigin`.
    func worldAxisDelta(
        from start: CGPoint,
        to end: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D
    ) throws -> Double

    /// The world point where `point` meets the plane through `planeOrigin`
    /// with normal `planeNormal`.
    func worldPlanePoint(
        at point: CGPoint,
        planeOrigin: Point3D,
        planeNormal: Vector3D
    ) throws -> Point3D

    /// The world point where `point` meets the plane through `anchor`
    /// perpendicular to the direction the frame is looking along.
    ///
    /// Only the frame knows that direction, so it is never reconstructed from
    /// a projection basis the caller happens to hold.
    func viewPlanePoint(at point: CGPoint, through anchor: Point3D) throws -> Point3D
}
