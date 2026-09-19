import Foundation
import SwiftCAD
import RupaCoreTypes

/// Turns one world-space motion into the local transforms that make a whole selection follow it.
///
/// Moving several objects together is a single rigid motion applied in world space, but each node
/// stores its placement relative to its own parent. Re-expressing the motion per node is what keeps
/// the selection's internal arrangement intact — otherwise nodes sitting under different parents
/// drift apart, and a node whose parent is itself rotated moves along the wrong axis.
public struct SceneNodeRelativeTransformPlanner: Sendable {
    /// The new local transforms that realise the requested world-space motion.
    public struct Plan: Sendable, Equatable {
        /// The nodes that actually move, in document order.
        public var transformedIDs: [SceneNodeID]
        public var localTransformsByID: [SceneNodeID: Transform3D]
    }

    public init() {}

    /// Plans the motion `worldDelta` for `ids`.
    ///
    /// A node that already sits below another node in `ids` is left out: its ancestor carries it, and
    /// transforming it as well would apply the motion to it twice.
    public func plan(
        hierarchy: SceneNodeHierarchy,
        ids: [SceneNodeID],
        worldDelta: Transform3D
    ) throws -> Plan {
        try worldDelta.validate()
        for id in ids {
            guard hierarchy.node(id) != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node \(id.description) cannot be transformed because it is missing."
                )
            }
            guard !hierarchy.isRootSceneNode(id) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "The scene root cannot be transformed."
                )
            }
        }

        let transformedIDs = hierarchy.outermostSceneNodeIDs(among: ids)
        guard !transformedIDs.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "A transform needs at least one scene node to move."
            )
        }

        var localTransformsByID: [SceneNodeID: Transform3D] = [:]
        for id in transformedIDs {
            guard let node = hierarchy.node(id) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node \(id.description) cannot be transformed because it is missing."
                )
            }
            // The motion is stated in world space, so it is carried into the node's parent space
            // before it can be composed with a local transform.
            let parentWorldTransform = try hierarchy.parentWorldTransform(of: id)
            let localDelta = try parentWorldTransform
                .inverse()
                .composed(with: worldDelta)
                .composed(with: parentWorldTransform)
            localTransformsByID[id] = try localDelta.composed(with: node.localTransform)
        }

        return Plan(
            transformedIDs: transformedIDs,
            localTransformsByID: localTransformsByID
        )
    }
}
