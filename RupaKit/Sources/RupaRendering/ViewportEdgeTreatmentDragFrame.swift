import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD

/// Measures source length along the world normal that draws the edge handle.
struct ViewportEdgeTreatmentDragFrame: Equatable, Sendable {
    let anchor: Point3D
    let direction: Vector3D
    let worldToSource: ScenePlacement

    init(anchor: Point3D, direction: Vector3D, modelTransform: ScenePlacement) {
        self.anchor = anchor
        self.direction = direction
        worldToSource = modelTransform.inverse
    }

    @MainActor
    func distance(from start: CGPoint, to end: CGPoint,
                  measure: some ViewportAffordanceMeasuring) throws -> Double {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Edge treatment requires finite pointer coordinates.")
        }
        let axis = try direction.normalized(tolerance: 1.0e-12)
        let delta = try measure.worldAxisDelta(
            from: start, to: end, axisOrigin: anchor, axisDirection: axis
        )
        let displacement = try ViewportWorldTransformAlgebra.transformedVector(axis * delta, by: worldToSource)
        let length = displacement.length
        guard length.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Edge treatment distance is not representable.")
        }
        return (delta < 0 ? -1 : 1) * length
    }
}
