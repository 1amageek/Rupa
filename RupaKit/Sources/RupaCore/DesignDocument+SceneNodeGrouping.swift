import Foundation
import SwiftCAD
import RupaCoreTypes

/// Document edits that restructure the scene tree or move several nodes at once.
///
/// The arithmetic lives in the planners; what is added here is the document's own rules — a pattern
/// array owns the placement of everything it generated, and the scene has to stay valid afterwards.
extension DesignDocument {
    /// Collects `memberIDs` under a new group node and returns its identifier.
    ///
    /// Nothing moves: each member keeps its world placement, expressed relative to the group instead
    /// of its former parent.
    @discardableResult
    public mutating func groupSceneNodes(
        name: String,
        memberIDs: [SceneNodeID],
        origin: Point3D? = nil,
        groupNodeID: SceneNodeID = SceneNodeID(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SceneNodeID {
        let plan = try SceneNodeGroupPlanner().plan(
            hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
            name: name,
            memberIDs: memberIDs,
            origin: origin,
            groupNodeID: groupNodeID
        )
        for id in plan.memberIDs {
            try requireSceneNodeIsNotPatternArrayOutput(
                id,
                reason: "Pattern array output scene nodes are grouped by the pattern source."
            )
        }
        try requireSceneNodeIsNotPatternArrayOutput(
            plan.parentID,
            reason: "A group cannot be added inside a pattern array output."
        )

        var groupNode = plan.groupNode
        groupNode.childIDs = []
        try productMetadata.insertSceneNode(
            groupNode,
            under: plan.parentID,
            at: plan.insertionIndex
        )
        for id in plan.memberIDs {
            try productMetadata.moveSceneNode(id, under: plan.groupNode.id, at: nil)
            try setSceneNodeLocalTransform(id, to: plan.memberLocalTransforms[id])
        }

        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return plan.groupNode.id
    }

    /// Dissolves the group `id`, handing its members back to the group's parent, and returns them.
    @discardableResult
    public mutating func ungroupSceneNode(
        id: SceneNodeID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        let plan = try SceneNodeUngroupPlanner().plan(
            hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
            groupNodeID: id
        )
        try requireSceneNodeIsNotPatternArrayOutput(
            id,
            reason: "Pattern array output scene nodes are structured by the pattern source."
        )

        let hiddenMemberIDs = Set(plan.hiddenMemberIDs)
        // Members are re-inserted back to front at the group's own position, so the order they had
        // inside the group is the order they take among their new siblings.
        for memberID in plan.memberIDs.reversed() {
            try productMetadata.moveSceneNode(
                memberID,
                under: plan.parentID,
                at: plan.insertionIndex
            )
            try setSceneNodeLocalTransform(memberID, to: plan.memberLocalTransforms[memberID])
            if hiddenMemberIDs.contains(memberID) {
                productMetadata.sceneNodes[memberID]?.isVisible = false
            }
        }
        try productMetadata.removeSceneNode(plan.groupNodeID)

        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return plan.memberIDs
    }

    /// Applies one world-space motion to `ids` and returns the nodes that moved.
    ///
    /// The selection moves as a single rigid body: the members hold their arrangement relative to one
    /// another regardless of where they sit in the tree.
    @discardableResult
    public mutating func transformSceneNodes(
        ids: [SceneNodeID],
        worldDelta: Transform3D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        let plan = try SceneNodeRelativeTransformPlanner().plan(
            hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
            ids: ids,
            worldDelta: worldDelta
        )
        for id in plan.transformedIDs {
            try requireSceneNodeIsNotPatternArrayOutput(
                id,
                reason: "Pattern array output scene node transforms are controlled by the pattern source."
            )
        }
        for id in plan.transformedIDs {
            try setSceneNodeLocalTransform(id, to: plan.localTransformsByID[id])
        }

        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return plan.transformedIDs
    }

    private mutating func setSceneNodeLocalTransform(
        _ id: SceneNodeID,
        to localTransform: Transform3D?
    ) throws {
        guard let localTransform else {
            throw EditorError(
                code: .commandInvalid,
                message: "Scene node \(id.description) was left without a planned transform."
            )
        }
        try localTransform.validate()
        guard productMetadata.sceneNodes[id] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node \(id.description) is missing."
            )
        }
        productMetadata.sceneNodes[id]?.localTransform = localTransform
    }

    private func requireSceneNodeIsNotPatternArrayOutput(
        _ id: SceneNodeID,
        reason: String
    ) throws {
        guard PatternArrayOwnershipResolver().sourceID(
            containingOutputSceneNode: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(code: .commandInvalid, message: reason)
        }
    }
}
