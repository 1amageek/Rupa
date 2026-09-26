import SwiftCAD
import RupaCoreTypes

/// The exact point and outward normal of a displayed face at a pick.
///
/// A viewport pick lands on the tessellated display and names the face drawn there. The point is
/// taken into the occurrence's source frame, Swift-CAD returns the nearest point of that face and
/// its outward normal, and both are placed back into the world.
public struct PlacedSurfacePointResolver: Sendable {
    public struct Result: Equatable, Sendable {
        public var point: Point3D
        public var outwardNormal: Vector3D
    }

    public init() {}

    public func exactPoint(
        near worldPoint: Point3D,
        onFace faceComponentID: SelectionComponentID,
        of occurrenceID: SceneOccurrenceID,
        document: DesignDocument,
        topology: TopologySnapshot
    ) throws -> Result {
        guard let evaluatedDocument = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "An exact surface point needs the evaluated document.")
        }
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        guard let occurrence = try hierarchy.resolvedOccurrences().first(where: { $0.id == occurrenceID }) else {
            throw EditorError(code: .referenceUnresolved, message: "The picked occurrence no longer exists.")
        }
        guard let face = topology.entries.first(where: {
            $0.kind == .face
                && $0.selectionComponentID == faceComponentID.rawValue
                && $0.selectionTarget()?.sceneNodeID == occurrence.sourceSceneNodeID
        }), let stableReference = face.stableReference else {
            throw EditorError(code: .referenceUnresolved, message: "The picked face is not part of the evaluated body.")
        }
        let frame = try SurfaceQueryEvaluator(tolerance: .standard).outwardFrame(
            nearestTo: try occurrence.worldTransform.inverse().applied(to: worldPoint),
            on: SurfaceReference(subshape: stableReference),
            in: evaluatedDocument
        )
        return Result(
            point: try occurrence.worldTransform.applied(to: frame.point),
            outwardNormal: try occurrence.worldTransform.applyingNormal(to: frame.outwardNormal)
                .normalized(tolerance: ModelingTolerance.standard.distance)
        )
    }
}
