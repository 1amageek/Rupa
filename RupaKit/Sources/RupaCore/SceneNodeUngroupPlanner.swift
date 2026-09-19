import Foundation
import SwiftCAD
import RupaCoreTypes

/// Works out how a group's members stand on their own once the group is gone.
///
/// Dissolving a group has to leave the scene looking untouched, so whatever the group contributed —
/// its placement and, when it was hidden, its concealment — is baked into each member before the
/// group is removed. This planner computes that; the document layer decides whether the removal is
/// permitted and carries it out.
public struct SceneNodeUngroupPlanner: Sendable {
    /// The tree edit that dissolves a group without moving or revealing anything.
    public struct Plan: Sendable, Equatable {
        public var groupNodeID: SceneNodeID
        /// The node the members are handed back to.
        public var parentID: SceneNodeID
        /// Where the members take the group's place among the parent's children.
        public var insertionIndex: Int
        /// The released members, in the order they had inside the group.
        public var memberIDs: [SceneNodeID]
        /// Each member's local transform re-expressed relative to the parent.
        public var memberLocalTransforms: [SceneNodeID: Transform3D]
        /// Members that were only out of sight because the group was hidden, and so must be hidden
        /// in their own right to keep the viewport unchanged.
        public var hiddenMemberIDs: [SceneNodeID]
    }

    public init() {}

    /// Plans the removal of the group `groupNodeID`.
    ///
    /// Only a node that carries no geometry of its own can be dissolved. Releasing the children of a
    /// body or a sketch would discard that geometry, which is a deletion, not an ungrouping.
    public func plan(
        hierarchy: SceneNodeHierarchy,
        groupNodeID: SceneNodeID
    ) throws -> Plan {
        guard let groupNode = hierarchy.node(groupNodeID) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node \(groupNodeID.description) cannot be ungrouped because it is missing."
            )
        }
        guard !hierarchy.isRootSceneNode(groupNodeID) else {
            throw EditorError(
                code: .commandInvalid,
                message: "The scene root cannot be ungrouped."
            )
        }
        guard groupNode.isGroupingNode else {
            throw EditorError(
                code: .commandInvalid,
                message: "Only a node that holds no geometry of its own can be ungrouped."
            )
        }
        guard let parentID = hierarchy.parentID(of: groupNodeID) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node \(groupNodeID.description) has no parent to release its members to."
            )
        }

        var memberLocalTransforms: [SceneNodeID: Transform3D] = [:]
        for id in groupNode.childIDs {
            guard let member = hierarchy.node(id) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Group member \(id.description) is missing."
                )
            }
            memberLocalTransforms[id] = try groupNode.localTransform.composed(with: member.localTransform)
        }

        return Plan(
            groupNodeID: groupNodeID,
            parentID: parentID,
            insertionIndex: hierarchy.node(parentID)?.childIDs.firstIndex(of: groupNodeID)
                ?? (hierarchy.node(parentID)?.childIDs.count ?? 0),
            memberIDs: groupNode.childIDs,
            memberLocalTransforms: memberLocalTransforms,
            hiddenMemberIDs: groupNode.isVisible ? [] : groupNode.childIDs
        )
    }
}
