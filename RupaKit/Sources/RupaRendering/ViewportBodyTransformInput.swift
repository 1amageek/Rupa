import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// A world-space transform applied to immutable, occurrence-scoped placements.
struct ViewportBodyTransformInput: Sendable {
    let identity: ViewportSpatialHandleIdentity
    let action: ViewportAffordanceAction
    let members: [ViewportObjectTransformMember]
    let bounds: ViewportObjectEditState

    init?(record: ViewportSpatialInteractionRecord) throws {
        if case .objectTransform(let action, let members, let bounds) = record.target {
            self.identity = record.identity
            self.action = action
            self.members = members
            self.bounds = bounds
            return
        }
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
        self.identity = record.identity
        self.action = target.action
        self.members = try resolved.map { member in
            guard let placement = member.placement else {
                throw RealityViewportSpatialBatch.invalid("A body transform has no placement.")
            }
            return .init(occurrenceID: member.occurrenceID, reference: .body(placement.featureID),
                         sceneNodeID: placement.sceneNodeID, baseLocalTransform: placement.baseLocalTransform,
                         parentWorldTransform: placement.parentWorldTransform, bounds: member.edit)
        }
        self.bounds = group ?? resolved[0].edit
    }

    @MainActor
    func mutation(from start: CGPoint, to end: CGPoint,
                  measure: some ViewportAffordanceMeasuring) throws -> Transform3D {
        let pivot = bounds.worldPoint(bounds.centerPoint)
        switch action {
        case .faceMove, .vertexMove:
            guard members.count == 1, let resize = members[0].resize else {
                throw RealityViewportSpatialBatch.invalid("The box resize baseline is unavailable.")
            }
            return try resize.mutation(action: action, from: start, to: end, measure: measure)
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
            if case .centerScale = action { centered = true } else { centered = false }
            let factor = 1 + delta * (centered ? 2 : 1) / extent
            guard extent.isFinite, extent > 0, factor.isFinite else {
                throw RealityViewportSpatialBatch.invalid("A body scale must remain finite with a nonzero baseline extent.")
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
        if isResize { return [] }
        // A singular preview can cross zero, but cannot become a placement.
        _ = try ViewportWorldTransformAlgebra.inverted(mutation)
        var result: [ViewportBodyPlacementDragTarget] = []
        var seen: Set<SceneNodeID> = []
        for member in members {
            guard seen.insert(member.sceneNodeID).inserted else {
                throw RealityViewportSpatialBatch.invalid("A body transform repeats or omits a placement.")
            }
            guard let local = try ViewportWorldTransformAlgebra.localTransform(applying: mutation,
                within: member.parentWorldTransform, to: member.baseLocalTransform) else { continue }
            result.append(.init(reference: member.reference, sceneNodeID: member.sceneNodeID,
                baseLocalTransform: member.baseLocalTransform, localTransform: local,
                baseParentWorldTransform: member.parentWorldTransform))
        }
        return result
    }

    var isResize: Bool {
        switch action { case .faceMove, .vertexMove: true; default: false }
    }

    func resizeCommit(mutation: Transform3D) throws -> ViewportBodyResizeDragTarget? {
        guard isResize, members.count == 1, let resize = members[0].resize else { return nil }
        return try resize.commit(mutation: mutation, member: members[0])
    }
}
