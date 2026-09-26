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
        case .translate, .rotate, .centerScale, .oneSidedScale,
             .translatePlane, .translateScreen, .uniformScale, .rotateScreen, .scalePlane: break
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

    /// The world axis a gizmo axis stands for: the mode frame's when a mode is active.
    private func axisVector(_ axis: ViewportCoordinateAxis) -> Vector3D {
        bounds.transformGizmo?.frame.axis(ViewportTransformGizmoConfiguration.axis(axis)) ?? axis.unitVector
    }

    private var increments: ViewportTransformGizmoConfiguration.Increments? {
        bounds.transformGizmo?.increments
    }

    @MainActor
    func mutation(from start: CGPoint, to end: CGPoint,
                  measure: some ViewportAffordanceMeasuring) throws -> Transform3D {
        let boundsCenter = bounds.worldPoint(bounds.centerPoint)
        let gizmo = bounds.transformGizmo
        let frame = gizmo?.frame ?? .world(at: boundsCenter)
        let pivot = frame.origin
        switch action {
        case .faceMove, .vertexMove:
            guard members.count == 1, let resize = members[0].handleResize else {
                throw RealityViewportSpatialBatch.invalid("The box resize baseline is unavailable.")
            }
            return try resize.mutation(action: action, from: start, to: end, measure: measure)
        case .translate(let axis):
            let direction = axisVector(axis)
            let delta = try measure.worldAxisDelta(from: start, to: end,
                axisOrigin: pivot, axisDirection: direction)
            return try ViewportWorldTransformAlgebra.translation(direction * rounded(distance: delta))
        case .translatePlane(let normal):
            let n = axisVector(normal)
            let first = try measure.worldPlanePoint(at: start, planeOrigin: pivot, planeNormal: n)
            let last = try measure.worldPlanePoint(at: end, planeOrigin: pivot, planeNormal: n)
            return try ViewportWorldTransformAlgebra.translation(roundedInFrame(last - first, frame: frame))
        case .translateScreen:
            let first = try measure.viewPlanePoint(at: start, through: pivot)
            let last = try measure.viewPlanePoint(at: end, through: pivot)
            return try ViewportWorldTransformAlgebra.translation(roundedInFrame(last - first, frame: frame))
        case .rotate(let axis):
            let direction = axisVector(axis)
            let first = try measure.worldPlanePoint(at: start, planeOrigin: pivot, planeNormal: direction) - pivot
            let last = try measure.worldPlanePoint(at: end, planeOrigin: pivot, planeNormal: direction) - pivot
            let a = try ViewportWorldTransformAlgebra.normalized(first, describing: "rotation start")
            let b = try ViewportWorldTransformAlgebra.normalized(last, describing: "rotation end")
            let angle = atan2(direction.dot(a.cross(b)), a.dot(b))
            return try ViewportWorldTransformAlgebra.rotation(axis: direction, radians: rounded(angle: angle), about: pivot)
        case .rotateScreen:
            // Both points lie in the view plane through the pivot, so their cross product is the
            // view axis signed by the turn and its length and dot product give the angle.
            let first = try measure.viewPlanePoint(at: start, through: pivot) - pivot
            let last = try measure.viewPlanePoint(at: end, through: pivot) - pivot
            let a = try ViewportWorldTransformAlgebra.normalized(first, describing: "rotation start")
            let b = try ViewportWorldTransformAlgebra.normalized(last, describing: "rotation end")
            let cross = a.cross(b)
            guard cross.length > 1.0e-9 else { return .identity }
            let axis = try ViewportWorldTransformAlgebra.normalized(cross, describing: "screen rotation axis")
            let angle = rounded(angle: atan2(cross.length, a.dot(b)))
            return try ViewportWorldTransformAlgebra.rotation(axis: axis, radians: angle, about: pivot)
        case .uniformScale:
            // The center box sits on the pivot, so the factor grows with the drag toward the
            // screen's upper right, one bounds half-span per doubling of size.
            let first = try measure.viewPlanePoint(at: start, through: pivot)
            let last = try measure.viewPlanePoint(at: end, through: pivot)
            let right = try measure.viewPlanePoint(at: CGPoint(x: start.x + 1, y: start.y), through: pivot) - first
            let up = try measure.viewPlanePoint(at: CGPoint(x: start.x, y: start.y - 1), through: pivot) - first
            let screen = try ViewportWorldTransformAlgebra.normalized(right, describing: "screen right")
            let screenUp = try ViewportWorldTransformAlgebra.normalized(up, describing: "screen up")
            let offsets = bounds.worldBoxCorners.map { ($0 - boundsCenter).length }
            let radius = offsets.max() ?? 0
            guard radius.isFinite, radius > ModelingTolerance.standard.distance else {
                throw RealityViewportSpatialBatch.invalid("A uniform scale needs bounds with a nonzero extent.")
            }
            let travel = (last - first).dot(screen) + (last - first).dot(screenUp)
            let factor = rounded(factor: 1 + travel / radius)
            return try scaleMatrix(frame, factors: Vector3D(x: factor, y: factor, z: factor))
        case .scalePlane(let normal):
            let n = axisVector(normal)
            let first = try measure.worldPlanePoint(at: start, planeOrigin: pivot, planeNormal: n) - pivot
            let last = try measure.worldPlanePoint(at: end, planeOrigin: pivot, planeNormal: n) - pivot
            let factor = rounded(factor: try ratio(last, first))
            var factors = Vector3D(x: factor, y: factor, z: factor)
            switch ViewportTransformGizmoConfiguration.axis(normal) {
            case .x: factors.x = 1
            case .y: factors.y = 1
            case .z: factors.z = 1
            }
            return try scaleMatrix(frame, factors: factors)
        case .centerScale(let axis), .oneSidedScale(let axis):
            let direction = axisVector(axis)
            let delta = try measure.worldAxisDelta(from: start, to: end,
                axisOrigin: pivot, axisDirection: direction)
            // The extent along the axis is read from the bounds' corners, so it holds for any frame.
            let offsets = bounds.worldBoxCorners.map { ($0 - boundsCenter).dot(direction) }
            let extent = (offsets.max() ?? 0) - (offsets.min() ?? 0)
            let centered: Bool
            if case .centerScale = action { centered = true } else { centered = false }
            let factor = rounded(factor: 1 + delta * (centered ? 2 : 1) / extent)
            guard extent.isFinite, extent > 0, factor.isFinite else {
                throw RealityViewportSpatialBatch.invalid("A body scale must remain finite with a nonzero baseline extent.")
            }
            var factors = Vector3D(x: 1, y: 1, z: 1)
            switch ViewportTransformGizmoConfiguration.axis(axis) {
            case .x: factors.x = factor
            case .y: factors.y = factor
            case .z: factors.z = factor
            }
            guard gizmo != nil else {
                // The combined gizmo scales along world axes about the bounds: center scale keeps
                // the center and one-sided scale keeps the far bounds face.
                let anchor = centered ? boundsCenter : boundsCenter + direction * (-extent / 2)
                return try scaleMatrix(.world(at: anchor), factors: factors)
            }
            // A mode scales about its pivot.
            return try scaleMatrix(frame, factors: factors)
        default:
            throw RealityViewportSpatialBatch.invalid("This handle has no placement transform contract.")
        }
    }

    /// The scale by `factors` along the frame axes about its origin. A drag may pass through a
    /// zero or negative factor while previewing, so the matrix is built without refusing collapse;
    /// `commits(mutation:)` refuses a collapsed placement when the drag is released.
    private func scaleMatrix(_ frame: SceneTransformFrame, factors: Vector3D) throws -> Transform3D {
        let axes = [frame.xAxis, frame.yAxis, frame.zAxis]
        let f = [factors.x, factors.y, factors.z]
        guard f.allSatisfy(\.isFinite) else {
            throw RealityViewportSpatialBatch.invalid("A body scale must remain finite.")
        }
        func component(_ v: Vector3D, _ i: Int) -> Double { i == 0 ? v.x : (i == 1 ? v.y : v.z) }
        var values = Transform3D.identity.matrix.values
        for row in 0..<3 {
            for column in 0..<3 {
                values[row * 4 + column] = (0..<3).reduce(0.0) {
                    $0 + component(axes[$1], row) * f[$1] * component(axes[$1], column)
                }
            }
        }
        let o = [frame.origin.x, frame.origin.y, frame.origin.z]
        for row in 0..<3 {
            values[row * 4 + 3] = o[row] - (0..<3).reduce(0.0) { $0 + values[row * 4 + $1] * o[$1] }
        }
        return Transform3D(matrix: try Matrix4x4(values: values))
    }

    /// The factor carrying the length of `from` to the length of `to`.
    private func ratio(_ to: Vector3D, _ from: Vector3D) throws -> Double {
        guard from.length > ModelingTolerance.standard.distance else {
            throw RealityViewportSpatialBatch.invalid("A scale drag must start away from the pivot.")
        }
        return to.length / from.length
    }

    private func rounded(distance: Double) -> Double {
        guard let step = increments?.distanceMeters, step > 0 else { return distance }
        return (distance / step).rounded() * step
    }

    private func rounded(angle: Double) -> Double {
        guard let step = increments?.angleRadians, step > 0 else { return angle }
        return (angle / step).rounded() * step
    }

    private func rounded(factor: Double) -> Double {
        guard let step = increments?.factor, step > 0 else { return factor }
        let snapped = (factor / step).rounded() * step
        // A factor never snaps to zero; the smallest step is the closest the drag can come.
        return snapped == 0 ? (factor < 0 ? -step : step) : snapped
    }

    /// A world move rounded per frame axis, so a snapped move is whole steps in the frame.
    private func roundedInFrame(_ move: Vector3D, frame: SceneTransformFrame) -> Vector3D {
        guard increments?.distanceMeters != nil else { return move }
        let components = frame.components(of: move)
        return frame.worldVector(Vector3D(
            x: rounded(distance: components.x),
            y: rounded(distance: components.y),
            z: rounded(distance: components.z)
        ))
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
        switch action {
        case .faceMove, .vertexMove: members.count == 1 && members[0].resize != nil
        default: false
        }
    }

    func resizeCommit(mutation: Transform3D) throws -> ViewportBodyResizeDragTarget? {
        guard isResize, members.count == 1, let resize = members[0].resize else { return nil }
        return try resize.commit(mutation: mutation, member: members[0])
    }
}
