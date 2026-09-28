import Foundation
import SwiftCAD
import RupaCoreTypes

/// The coordinate flow the curve commands share with Projection and Cut: a sketch's plane goes
/// through its scene node's world placement, a body's evaluated faces and edges are read in the
/// body's source frame and placed by its scene node's world placement, and a created curve is
/// authored in world space, its node's placement cancelling its parent's so it applies once.
extension DesignDocument {
    func worldPlacement(of id: SceneNodeID) throws -> Transform3D {
        try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: id)
    }

    /// The sketch plane of a curve target in world space.
    func placedSketchSystem(for target: SelectionTarget, plane: SketchPlane) throws -> SketchPlaneCoordinateSystem {
        try placedSketchPlane(plane, through: worldPlacement(of: target.sceneNodeID))
    }

    /// Creates a spatial path whose points are world coordinates.
    mutating func createWorldSpatialPath(
        name: String, path: SpatialPathFeature, objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        let featureID = try createSpatialPath(name: name, path: path, objectRegistry: objectRegistry)
        guard let nodeID = productMetadata.sceneNodes.first(where: { $0.value.reference?.featureID == featureID })?.key else {
            throw EditorError(code: .referenceUnresolved, message: "A created path has no scene node.")
        }
        let parent = try SceneNodeHierarchy(metadata: productMetadata).parentWorldTransform(of: nodeID)
        try setSceneNodeTransform(id: nodeID, localTransform: try parent.inverse(), objectRegistry: objectRegistry)
        return featureID
    }

    /// Whether two placements are the same within the modeling tolerance.
    func placementsMatch(_ a: Transform3D, _ b: Transform3D) -> Bool {
        zip(a.matrix.values, b.matrix.values).allSatisfy { abs($0 - $1) <= modelingSettings.tolerance.relative * max(1, abs($0)) }
    }
}
