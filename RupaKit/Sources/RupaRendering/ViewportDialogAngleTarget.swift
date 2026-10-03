import RupaCore

/// A dialog angle handle as a prepared interaction: the circle's centre and axis, the point the
/// angle is measured from, and the angle the handle stands at.
struct ViewportDialogAngleTarget: Sendable {
    let id: String
    let center: Point3D
    let axis: Vector3D
    let referencePoint: Point3D
    let angleRadians: Double
}
