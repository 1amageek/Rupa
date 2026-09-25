import Foundation
import SwiftCAD

/// The placement a measured point was picked under, which the saved anchor must follow.
///
/// A point picked on displayed geometry is stored in that geometry's local frame, so moving the
/// scene node or component occurrence later moves the saved measurement with it. A point picked
/// on a construction plane or in empty space names no placement and stays fixed in world space.
public enum MeasurementPickPlacement: Equatable, Sendable {
    case world
    case sceneNode(SceneNodeID)
    case occurrence(SceneOccurrenceID)
}

extension MeasurementAnchor {
    /// Builds the persistent anchor for a world point picked under `placement`.
    ///
    /// The local point is computed through the same validated placement the resolver later
    /// applies, so the anchor resolves back to `worldPoint` in the document it was built from.
    public static func picked(
        _ worldPoint: Point3D,
        under placement: MeasurementPickPlacement,
        in hierarchy: SceneNodeHierarchy,
        role: Role = .point
    ) throws -> MeasurementAnchor {
        try worldPoint.validate()
        switch placement {
        case .world:
            return .worldPoint(worldPoint, role: role)
        case .sceneNode(let sceneNodeID):
            let frame = try ScenePlacement(hierarchy.worldTransform(of: sceneNodeID))
            return .sceneLocalPoint(
                try localPoint(worldPoint, in: frame),
                in: sceneNodeID,
                role: role
            )
        case .occurrence(let occurrenceID):
            guard let occurrence = try hierarchy.resolvedOccurrences().first(where: { $0.id == occurrenceID }) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "The measured occurrence \(occurrenceID.rawValue) is no longer in the scene."
                )
            }
            let frame = try ScenePlacement(occurrence.worldTransform)
            return .sceneLocalPoint(
                try localPoint(worldPoint, in: frame),
                in: occurrence.sceneNodeID,
                occurrenceID: occurrence.id,
                role: role
            )
        }
    }

    private static func localPoint(_ worldPoint: Point3D, in frame: ScenePlacement) throws -> Point3D {
        let local = frame.inversePoint(worldPoint)
        try local.validate()
        return local
    }
}

extension SnapCandidate {
    /// The placement a snapped point belongs to.
    ///
    /// A snap names its geometry through its source references. When they name exactly one scene
    /// node, the point follows that node. When they name none, or name geometry on different nodes
    /// (an intersection between two placed objects), no single placement owns the point and it is
    /// kept in world space. Snaps onto saved measurements, axes, planes and surface frames name no
    /// owning placement either.
    public func measurementPickPlacement(in hierarchy: SceneNodeHierarchy) -> MeasurementPickPlacement {
        var sceneNodeIDs: Set<SceneNodeID> = []
        if let topologySource {
            sceneNodeIDs.insert(topologySource.sceneNodeID)
        }
        for sketchSource in [source, relatedSource].compactMap({ $0 }) {
            if let sceneNodeID = sketchSource.sceneNodeID ?? hierarchy.presentingSceneNodeID(for: sketchSource.featureID) {
                sceneNodeIDs.insert(sceneNodeID)
            }
        }
        if let regionSource,
           let sceneNodeID = regionSource.sceneNodeID ?? hierarchy.presentingSceneNodeID(for: regionSource.featureID) {
            sceneNodeIDs.insert(sceneNodeID)
        }
        if let sceneNodeID = surfaceTrimSource?.sceneNodeID {
            sceneNodeIDs.insert(sceneNodeID)
        }
        guard sceneNodeIDs.count == 1, let sceneNodeID = sceneNodeIDs.first else {
            return .world
        }
        return .sceneNode(sceneNodeID)
    }
}
