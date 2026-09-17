import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// A world-space transform applied to immutable, occurrence-scoped placements.
struct ViewportBodyTransformInput: Sendable {
    let target: ViewportAffordanceTarget
    let members: [ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember]
    let bounds: ViewportObjectEditState

    init?(record: ViewportSpatialInteractionRecord) throws {
        guard case .affordance(let target, let members, let group, let single) = record.target else {
            return nil
        }
        switch target.action {
        case .translate, .rotate, .centerScale, .oneSidedScale: break
        default: return nil
        }
        var resolved = members
        if resolved.count == 1, resolved[0].placement == nil {
            resolved[0].placement = single
        }
        guard !resolved.isEmpty, resolved.allSatisfy({ $0.placement != nil }) else {
            throw RealityViewportSpatialBatch.invalid("A body transform has no complete placement baseline.")
        }
        self.target = target
        self.members = resolved
        self.bounds = group ?? resolved[0].edit
    }

    @MainActor
    func mutation(from start: CGPoint, to end: CGPoint,
                  measure: some ViewportAffordanceMeasuring) throws -> Transform3D {
        let pivot = bounds.worldPoint(bounds.centerPoint)
        switch target.action {
        case .translate(let axis):
            let delta = try measure.worldAxisDelta(from: start, to: end,
                axisOrigin: pivot, axisDirection: axis.unitVector)
            return try ViewportWorldTransformAlgebra.translation(axis.unitVector * delta)
        case .rotate(let axis):
            let first = try measure.worldPlanePoint(at: start, planeOrigin: pivot, planeNormal: axis.unitVector) - pivot
            let last = try measure.worldPlanePoint(at: end, planeOrigin: pivot, planeNormal: axis.unitVector) - pivot
            let a = try ViewportWorldTransformAlgebra.normalized(first, describing: "rotation start")
            let b = try ViewportWorldTransformAlgebra.normalized(last, describing: "rotation end")
            let angle = atan2(axis.unitVector.dot(a.cross(b)), a.dot(b))
            return try ViewportWorldTransformAlgebra.rotation(axis: axis.unitVector, radians: angle, about: pivot)
        case .centerScale(let axis), .oneSidedScale(let axis):
            let delta = try measure.worldAxisDelta(from: start, to: end,
                axisOrigin: pivot, axisDirection: axis.unitVector)
            let extent: Double
            switch axis {
            case .x: extent = Double(bounds.xMax - bounds.xMin)
            case .y: extent = Double(bounds.yMax - bounds.yMin)
            case .z: extent = Double(bounds.zMax - bounds.zMin)
            }
            let centered: Bool
            if case .centerScale = target.action { centered = true } else { centered = false }
            let factor = 1 + delta * (centered ? 2 : 1) / extent
            guard extent.isFinite, extent > 0, factor.isFinite, factor > 1e-3 else {
                throw RealityViewportSpatialBatch.invalid("A body scale must remain finite and positive.")
            }
            let anchor = centered ? pivot : pivot + axis.unitVector * (-extent / 2)
            let direction = axis.unitVector
            let components = [direction.x, direction.y, direction.z]
            let offset = anchor - Point3D.origin
            let shift = direction * ((1 - factor) * offset.dot(direction))
            var values = Transform3D.identity.matrix.values
            for index in 0..<3 { values[index * 4 + index] = 1 + (factor - 1) * components[index] }
            values[3] = shift.x; values[7] = shift.y; values[11] = shift.z
            return Transform3D(matrix: try Matrix4x4(values: values))
        default:
            throw RealityViewportSpatialBatch.invalid("This handle has no placement transform contract.")
        }
    }

    func commits(mutation: Transform3D) throws -> [ViewportBodyPlacementDragTarget] {
        var result: [ViewportBodyPlacementDragTarget] = []
        var seen: Set<SceneNodeID> = []
        for member in members {
            guard let baseline = member.placement, seen.insert(baseline.sceneNodeID).inserted else {
                throw RealityViewportSpatialBatch.invalid("A body transform repeats or omits a placement.")
            }
            guard let local = try ViewportWorldTransformAlgebra.localTransform(applying: mutation,
                within: baseline.parentWorldTransform, to: baseline.baseLocalTransform) else { continue }
            result.append(.init(featureID: baseline.featureID, sceneNodeID: baseline.sceneNodeID,
                baseLocalTransform: baseline.baseLocalTransform, localTransform: local,
                baseParentWorldTransform: baseline.parentWorldTransform))
        }
        return result
    }
}
