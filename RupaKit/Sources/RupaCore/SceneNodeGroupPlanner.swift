import Foundation
import SwiftCAD
import RupaCoreTypes

/// Works out where a new group node belongs and how its members are re-expressed underneath it.
///
/// Grouping is a restructuring of the scene tree, not a move: what the user sees must be identical
/// before and after. That holds only if every member's local transform is rebased from its old
/// parent into the group, which is what this planner computes. It reads the hierarchy and returns a
/// plan; applying it, and deciding whether the document permits it, belongs to the document layer.
public struct SceneNodeGroupPlanner: Sendable {
    /// The tree edit that creates a group without moving any geometry.
    public struct Plan: Sendable, Equatable {
        /// The group node itself, already carrying its members and its placement under `parentID`.
        public var groupNode: SceneNode
        /// The node the group is inserted under — the nearest node that already contains every member.
        public var parentID: SceneNodeID
        /// Where the group takes its place among the parent's children.
        public var insertionIndex: Int
        /// Each member's local transform re-expressed relative to the group.
        public var memberLocalTransforms: [SceneNodeID: Transform3D]

        public var memberIDs: [SceneNodeID] {
            groupNode.childIDs
        }
    }

    public init() {}

    /// Plans a group of `memberIDs` named `name`.
    ///
    /// A member that already sits below another member is left out: it travels with its ancestor, and
    /// re-parenting it as well would pull it out of a structure the user did not ask to dismantle.
    ///
    /// - Parameter origin: Where the group's own origin sits in world space. Supplying the centre of
    ///   the selection makes the group's position read as the position of what it contains; leaving it
    ///   `nil` places the group exactly where its parent is.
    public func plan(
        hierarchy: SceneNodeHierarchy,
        name: String,
        memberIDs: [SceneNodeID],
        origin: Point3D? = nil,
        groupNodeID: SceneNodeID = SceneNodeID()
    ) throws -> Plan {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "A group needs a name."
            )
        }
        for id in memberIDs {
            guard hierarchy.node(id) != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node \(id.description) cannot be grouped because it is missing."
                )
            }
            guard !hierarchy.isRootSceneNode(id) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "The scene root cannot be grouped."
                )
            }
            guard id != groupNodeID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A group cannot contain itself."
                )
            }
        }

        let orderedMemberIDs = hierarchy.outermostSceneNodeIDs(among: memberIDs)
        guard !orderedMemberIDs.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "A group needs at least one member."
            )
        }
        guard let parentID = hierarchy.nearestCommonAncestorID(of: orderedMemberIDs) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Scene nodes can only be grouped when they share a common ancestor."
            )
        }

        let parentWorldTransform = try hierarchy.worldTransform(of: parentID)
        let groupWorldTransform: Transform3D
        let groupLocalTransform: Transform3D
        if let origin {
            try origin.validate()
            groupWorldTransform = try Transform3D.translation(
                Vector3D(x: origin.x, y: origin.y, z: origin.z)
            )
            groupLocalTransform = try parentWorldTransform.inverse().composed(with: groupWorldTransform)
        } else {
            groupWorldTransform = parentWorldTransform
            groupLocalTransform = .identity
        }

        let groupWorldInverse = try groupWorldTransform.inverse()
        var memberLocalTransforms: [SceneNodeID: Transform3D] = [:]
        for id in orderedMemberIDs {
            let worldTransform = try hierarchy.worldTransform(of: id)
            memberLocalTransforms[id] = try groupWorldInverse.composed(with: worldTransform)
        }

        return Plan(
            groupNode: SceneNode(
                id: groupNodeID,
                name: name,
                childIDs: orderedMemberIDs,
                localTransform: groupLocalTransform
            ),
            parentID: parentID,
            insertionIndex: insertionIndex(
                forMembers: orderedMemberIDs,
                under: parentID,
                hierarchy: hierarchy
            ),
            memberLocalTransforms: memberLocalTransforms
        )
    }

    /// The group takes the place of the first member that already sat under the parent, so a grouped
    /// selection stays where the user last saw it in the outliner.
    private func insertionIndex(
        forMembers memberIDs: [SceneNodeID],
        under parentID: SceneNodeID,
        hierarchy: SceneNodeHierarchy
    ) -> Int {
        guard let childIDs = hierarchy.node(parentID)?.childIDs else {
            return 0
        }
        let memberIDSet = Set(memberIDs)
        guard let index = childIDs.firstIndex(where: { memberIDSet.contains($0) }) else {
            return childIDs.count
        }
        return index
    }
}
