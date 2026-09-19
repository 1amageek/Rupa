import Foundation
import SwiftCAD

/// Measures where a selection actually sits in the scene.
///
/// Body snapshots are produced in the geometry's own coordinates, before the scene tree places
/// them, so a selection's extent is only known once each body is carried through its node's world
/// transform. This resolver does that walk and nothing else; deciding what to do with the result —
/// framing a view, choosing a rotation pivot — belongs to the caller.
public struct SceneNodeSelectionBoundsResolver: Sendable {
    public init() {}

    /// The world-space box enclosing every body under `sceneNodeIDs`.
    ///
    /// Throws when the selection encloses no measured geometry. A selection of sketches or empty
    /// groups has no extent, and answering with the world origin would silently rotate the model
    /// around a point the user never chose.
    public func worldBounds(
        of sceneNodeIDs: [SceneNodeID],
        hierarchy: SceneNodeHierarchy,
        bodySnapshots: [FeatureID: BodyDisplaySnapshot]
    ) throws -> SceneNodeWorldBounds {
        var measuredIDs: Set<SceneNodeID> = []
        var bounds: SceneNodeWorldBounds?

        for selectedID in sceneNodeIDs {
            for nodeID in hierarchy.subtreeIDs(of: selectedID) {
                guard measuredIDs.insert(nodeID).inserted,
                      let node = hierarchy.node(nodeID),
                      let featureID = node.reference?.featureID,
                      let snapshot = bodySnapshots[featureID] else {
                    continue
                }
                let worldTransform = try hierarchy.worldTransform(of: nodeID)
                let corners = try Self.sourceBounds(snapshot.bounds).corners.map { corner in
                    try worldTransform.applied(to: corner)
                }
                guard let placed = SceneNodeWorldBounds(containing: corners) else {
                    continue
                }
                bounds = bounds.map { $0.union(placed) } ?? placed
            }
        }

        guard let bounds else {
            throw EditorError(
                code: .commandInvalid,
                message: "The selection encloses no evaluated geometry to measure."
            )
        }
        return bounds
    }

    /// The world-space middle of `sceneNodeIDs`, which is the pivot a rotation turns around.
    public func worldCenter(
        of sceneNodeIDs: [SceneNodeID],
        hierarchy: SceneNodeHierarchy,
        bodySnapshots: [FeatureID: BodyDisplaySnapshot]
    ) throws -> Point3D {
        try worldBounds(
            of: sceneNodeIDs,
            hierarchy: hierarchy,
            bodySnapshots: bodySnapshots
        ).center
    }

    private static func sourceBounds(
        _ bounds: BodyDisplaySnapshot.Bounds
    ) -> SceneNodeWorldBounds {
        SceneNodeWorldBounds(
            minimum: Point3D(x: bounds.minX, y: bounds.minY, z: bounds.minZ),
            maximum: Point3D(x: bounds.maxX, y: bounds.maxY, z: bounds.maxZ)
        )
    }
}
