import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD

/// A source-length scrubber, independent of the body's generating feature.
struct ViewportEdgeTreatmentDragFrame: Equatable, Sendable {
    let anchor: Point3D
    let worldToSource: ScenePlacement

    init(anchor: Point3D, modelTransform: ScenePlacement) {
        self.anchor = anchor
        worldToSource = modelTransform.inverse
    }

    @MainActor
    func distance(from start: CGPoint, to end: CGPoint,
                  measure: some ViewportAffordanceMeasuring) throws -> Double {
        guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Edge treatment requires finite pointer coordinates.")
        }
        let horizontalEnd = CGPoint(x: end.x, y: start.y)
        let first = try measure.viewPlanePoint(at: start, through: anchor)
        let last = try measure.viewPlanePoint(at: horizontalEnd, through: anchor)
        let displacement = try ViewportWorldTransformAlgebra.transformedVector(last - first, by: worldToSource)
        let length = displacement.length
        guard length.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Edge treatment distance is not representable.")
        }
        return (end.x >= start.x ? 1 : -1) * length
    }
}
