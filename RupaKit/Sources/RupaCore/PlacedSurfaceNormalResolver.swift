import SwiftCAD
import RupaCoreTypes

/// The exact outward normal of a displayed body at a picked point.
///
/// A viewport pick lands on the tessellated display; the normal comes from Swift-CAD instead: the
/// point is taken into the occurrence's source frame, projected onto each face of the presented
/// body with the kernel's surface query, and the nearest face's surface normal is oriented by the
/// face and placed back into the world.
public struct PlacedSurfaceNormalResolver: Sendable {
    public init() {}

    public func outwardNormal(
        at worldPoint: Point3D,
        on occurrenceID: SceneOccurrenceID,
        document: DesignDocument,
        topology: TopologySnapshot
    ) throws -> Vector3D {
        guard let evaluatedDocument = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "A surface normal needs the evaluated document.")
        }
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        guard let occurrence = try hierarchy.resolvedOccurrences().first(where: { $0.id == occurrenceID }) else {
            throw EditorError(code: .referenceUnresolved, message: "The picked occurrence no longer exists.")
        }
        let localPoint = try occurrence.worldTransform.inverse().applied(to: worldPoint)
        let faces = topology.entries.compactMap { entry -> StableSubshapeReference? in
            guard entry.kind == .face,
                  entry.selectionTarget()?.sceneNodeID == occurrence.sourceSceneNodeID else {
                return nil
            }
            return entry.stableReference
        }
        let evaluator = SurfaceQueryEvaluator(tolerance: .standard)
        var nearest: (distance: Double, normal: Vector3D)?
        var lastFailure: (any Error)?
        for face in faces {
            let reference = SurfaceReference(subshape: face)
            do {
                let projection = try evaluator.closestPoint(to: localPoint, on: reference, in: evaluatedDocument)
                guard nearest.map({ projection.distance < $0.distance }) ?? true else { continue }
                let resolved = try evaluator.resolve(reference, in: evaluatedDocument)
                let reversed = evaluatedDocument.brep.faces[resolved.faceID]?.orientation != .forward
                nearest = (projection.distance, reversed ? projection.frame.normal * -1 : projection.frame.normal)
            } catch {
                // A face the point cannot be projected onto is not the face it lies on; only a pick
                // no face accepts is a failure.
                lastFailure = error
            }
        }
        guard let nearest else {
            throw lastFailure ?? EditorError(code: .referenceUnresolved, message: "The picked object presents no faces.")
        }
        return try occurrence.worldTransform.applyingNormal(to: nearest.normal)
            .normalized(tolerance: ModelingTolerance.standard.distance)
    }
}
