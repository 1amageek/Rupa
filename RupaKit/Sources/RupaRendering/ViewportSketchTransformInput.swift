import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// Native input owner for one sketch transform gesture.
///
/// The record is captured at press and never re-read from a later frame:
/// `query` names the single native camera question this role asks per update,
/// `worldMutation(for:)` turns the mounted frame's answer into a world
/// mutation, and `commit(worldMutation:)` converts that mutation into the scene
/// node's new local frame exactly once, at release. Every refusal is typed and
/// none is clamped, because a clamped drag would commit a transform the pointer
/// never described.
struct ViewportSketchTransformInput: Sendable {
    /// The one native camera query this role needs for each drag update.
    enum Query: Equatable, Sendable {
        case worldAxisDelta(origin: Point3D, direction: Vector3D)
        case worldPlanePoint(origin: Point3D, normal: Vector3D)
    }

    /// The mounted frame's answer to that query, read back by the viewport.
    enum Sample: Equatable, Sendable {
        case worldAxisDelta(Double)
        case worldPlanePoints(start: Point3D, current: Point3D)
    }

    /// A sketch scaled below this factor collapses into a frame no later drag
    /// can recover, so the update is refused rather than clamped.
    static let minimumScaleFactor = 1.0e-3
    /// A corner this close to the pivot cannot name a scale direction.
    static let minimumScaleRadius = 1.0e-9
    /// Inside this radius the in-plane angle is numerical noise, so the
    /// rotation update is refused instead of reporting an arbitrary turn.
    static let minimumRotationRadius = 1.0e-6

    let baseline: ViewportSketchTransformBaseline

    init?(record: ViewportSpatialInteractionRecord) throws {
        guard case .sketchTransform(let baseline) = record.target else { return nil }
        try baseline.validate()
        self.baseline = baseline
    }

    var identity: ViewportSketchTransformHandleIdentity { baseline.identity }

    var query: Query {
        get throws {
            switch baseline.geometry {
            case .translate(let direction):
                return .worldAxisDelta(
                    origin: baseline.pivot,
                    direction: try ViewportWorldTransformAlgebra.normalized(
                        direction, describing: "translation axis"
                    )
                )
            case .scale(let direction, _):
                return .worldAxisDelta(
                    origin: baseline.pivot,
                    direction: try ViewportWorldTransformAlgebra.normalized(
                        direction, describing: "scale axis"
                    )
                )
            case .rotate:
                return .worldPlanePoint(origin: baseline.pivot, normal: try rotationBasis().axis)
            }
        }
    }

    func worldMutation(for sample: Sample) throws -> Transform3D {
        switch (baseline.geometry, sample) {
        case (.translate(let direction), .worldAxisDelta(let delta)):
            guard delta.isFinite else {
                throw RealityViewportSpatialBatch.invalid("A sketch translation delta is not finite.")
            }
            let axis = try ViewportWorldTransformAlgebra.normalized(direction, describing: "translation axis")
            return try ViewportWorldTransformAlgebra.translation(axis * delta)
        case (.scale(let direction, let baseDistance), .worldAxisDelta(let delta)):
            _ = try ViewportWorldTransformAlgebra.normalized(direction, describing: "scale axis")
            guard delta.isFinite, baseDistance.isFinite, baseDistance > Self.minimumScaleRadius else {
                throw RealityViewportSpatialBatch.invalid("A sketch scale delta is not measurable.")
            }
            let factor = (baseDistance + delta) / baseDistance
            guard factor.isFinite, factor > Self.minimumScaleFactor else {
                throw RealityViewportSpatialBatch.invalid("A sketch scale below the positive floor is refused.")
            }
            return try ViewportWorldTransformAlgebra.scale(factor, about: baseline.pivot)
        case (.rotate, .worldPlanePoints(let start, let current)):
            let basis = try rotationBasis()
            let from = try angle(of: start, in: basis)
            let to = try angle(of: current, in: basis)
            let delta = to - from
            guard delta.isFinite else {
                throw RealityViewportSpatialBatch.invalid("A sketch rotation angle is not finite.")
            }
            // The drawn affordance is a quarter turn measured from the press
            // point, so the shorter signed turn is the one the pointer named.
            let shortest = atan2(sin(delta), cos(delta))
            guard shortest.isFinite else {
                throw RealityViewportSpatialBatch.invalid("A sketch rotation angle is not finite.")
            }
            return try ViewportWorldTransformAlgebra.rotation(
                axis: basis.axis, radians: shortest, about: baseline.pivot
            )
        case (.translate, _), (.scale, _), (.rotate, _):
            throw RealityViewportSpatialBatch.invalid(
                "A sketch transform sample does not answer the role's query."
            )
        }
    }

    /// Converts a world mutation into the scene node's new local frame, which
    /// the shared algebra composes for both transform gizmos. Returns `nil`
    /// when the mutation leaves the frame unchanged, so a released gesture
    /// that moved nothing writes no undo step.
    func commit(worldMutation: Transform3D) throws -> ViewportSketchTransformDragTarget? {
        guard let localTransform = try ViewportWorldTransformAlgebra.localTransform(
            applying: worldMutation,
            within: baseline.parentWorldTransform,
            to: baseline.baseLocalTransform
        ) else {
            return nil
        }
        return ViewportSketchTransformDragTarget(
            featureID: baseline.identity.featureID,
            sceneNodeID: baseline.identity.sceneNodeID,
            baseLocalTransform: baseline.baseLocalTransform,
            localTransform: localTransform
        )
    }

    private func rotationBasis() throws -> (abscissa: Vector3D, ordinate: Vector3D, axis: Vector3D) {
        guard case .rotate(let planeStart, let planeEnd) = baseline.geometry else {
            throw RealityViewportSpatialBatch.invalid("A sketch transform role has no rotation plane.")
        }
        let abscissa = try ViewportWorldTransformAlgebra.normalized(planeStart, describing: "rotation plane")
        let axis = try ViewportWorldTransformAlgebra.normalized(
            abscissa.cross(planeEnd), describing: "rotation axis"
        )
        let ordinate = try ViewportWorldTransformAlgebra.normalized(
            axis.cross(abscissa), describing: "rotation plane"
        )
        return (abscissa, ordinate, axis)
    }

    private func angle(
        of point: Point3D, in basis: (abscissa: Vector3D, ordinate: Vector3D, axis: Vector3D)
    ) throws -> Double {
        guard point.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A sketch rotation point is not finite.")
        }
        let offset = point - baseline.pivot
        let abscissa = offset.dot(basis.abscissa)
        let ordinate = offset.dot(basis.ordinate)
        let radius = hypot(abscissa, ordinate)
        guard radius.isFinite, radius > Self.minimumRotationRadius else {
            throw RealityViewportSpatialBatch.invalid("A sketch rotation point coincides with its pivot.")
        }
        return atan2(ordinate, abscissa)
    }
}
