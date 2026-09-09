import Foundation
import RupaCore
import RupaViewportScene

/// Projection-free world geometry of one sketch transform handle, prepared once
/// per frame by the overlay producer and read back unchanged by the input owner
/// for the whole gesture.
///
/// Every member is camera independent: the drag reads the mounted frame for the
/// screen-to-world answers and never re-derives the baseline from a later
/// frame, so a camera move during the gesture cannot change what is committed.
struct ViewportSketchTransformBaseline: Sendable {
    enum Geometry: Sendable {
        /// Unit world direction the translation is measured along.
        case translate(direction: Vector3D)
        /// Ordered world plane vectors. The drawn arc runs from `planeStart`
        /// toward `planeEnd`, and the rotation turns about their cross product.
        case rotate(planeStart: Vector3D, planeEnd: Vector3D)
        /// Unit world direction from the pivot to the corner, and the
        /// pivot-to-corner distance the scale factor is measured against.
        case scale(direction: Vector3D, baseDistance: Double)
    }

    let identity: ViewportSketchTransformHandleIdentity
    let baseLocalTransform: Transform3D
    let parentWorldTransform: Transform3D
    let pivot: Point3D
    let geometry: Geometry

    init(
        identity: ViewportSketchTransformHandleIdentity,
        baseLocalTransform: Transform3D,
        parentWorldTransform: Transform3D,
        pivot: Point3D,
        geometry: Geometry
    ) {
        self.identity = identity
        self.baseLocalTransform = baseLocalTransform
        self.parentWorldTransform = parentWorldTransform
        self.pivot = pivot
        self.geometry = geometry
    }

    /// Refuses a baseline the gesture could not answer for. A registered handle
    /// is pickable, so an unusable one would be a silent no-op drag rather than
    /// a reported failure.
    func validate() throws {
        guard pivot.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A sketch transform pivot is not finite.")
        }
        for value in baseLocalTransform.matrix.values where !value.isFinite {
            throw RealityViewportSpatialBatch.invalid("A sketch transform baseline frame is not finite.")
        }
        // The parent frame must invert for the commit to reach the local frame,
        // so its representability is settled at preparation, not at release.
        _ = try ViewportWorldTransformAlgebra.inverted(parentWorldTransform)
        switch geometry {
        case .translate(let direction):
            _ = try ViewportWorldTransformAlgebra.normalized(direction, describing: "translation axis")
        case .rotate(let planeStart, let planeEnd):
            let start = try ViewportWorldTransformAlgebra.normalized(planeStart, describing: "rotation plane")
            let end = try ViewportWorldTransformAlgebra.normalized(planeEnd, describing: "rotation plane")
            _ = try ViewportWorldTransformAlgebra.normalized(start.cross(end), describing: "rotation axis")
        case .scale(let direction, let baseDistance):
            _ = try ViewportWorldTransformAlgebra.normalized(direction, describing: "scale axis")
            guard baseDistance.isFinite, baseDistance > ViewportSketchTransformInput.minimumScaleRadius else {
                throw RealityViewportSpatialBatch.invalid("A sketch scale handle has no measurable radius.")
            }
        }
    }
}
