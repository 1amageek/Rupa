import SwiftCAD
import RupaCoreTypes

/// Where a click on a displayed face places an Isoparam line: the face, as a selection target, and
/// the fraction of its extent along the line's direction at the clicked point.
///
/// The point is taken into the occurrence's source frame and Swift-CAD reads its parameter on the
/// face (`IsoparamPlacementQuery`), so the line runs through the point clicked.
public struct IsoparamPlacementResolver: Sendable {
    public struct Placement: Equatable, Sendable {
        public var face: SelectionTarget
        public var fraction: Double
    }

    public init() {}

    public func placement(
        near worldPoint: Point3D,
        onFace faceComponentID: SelectionComponentID,
        of occurrenceID: SceneOccurrenceID,
        direction: SurfaceParameterDirection,
        document: DesignDocument,
        topology: TopologySnapshot
    ) throws -> Placement {
        guard let evaluatedDocument = topology.evaluatedDocument else {
            throw EditorError(code: .referenceUnresolved, message: "Isoparam needs the evaluated document.")
        }
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        guard let occurrence = try hierarchy.resolvedOccurrences().first(where: { $0.id == occurrenceID }) else {
            throw EditorError(code: .referenceUnresolved, message: "The clicked occurrence no longer exists.")
        }
        guard let entry = topology.entries.first(where: {
            $0.kind == .face
                && $0.selectionComponentID == faceComponentID.rawValue
                && $0.selectionTarget()?.sceneNodeID == occurrence.sourceSceneNodeID
        }), let stableReference = entry.stableReference, let face = entry.selectionTarget() else {
            throw EditorError(code: .referenceUnresolved, message: "The clicked face is not part of the evaluated body.")
        }
        do {
            let fraction = try IsoparamPlacementQuery(tolerance: document.modelingSettings.tolerance).fraction(
                at: try occurrence.worldTransform.inverse().applied(to: worldPoint),
                on: SurfaceReference(subshape: stableReference),
                direction: direction,
                in: evaluatedDocument
            )
            return Placement(face: face, fraction: fraction)
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "Isoparam: \(error.message)")
        }
    }
}
