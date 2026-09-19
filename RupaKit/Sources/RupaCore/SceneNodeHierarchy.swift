import Foundation
import SwiftCAD
import RupaCoreTypes

/// A read model of the scene tree: who parents whom, and where each node ends up in world space.
///
/// Placement questions all need the same three answers — a node's parent, the parent's accumulated
/// transform, and whether one node already sits under another. Keeping them in one type means the
/// commands that move and re-parent nodes never re-derive the tree themselves, and never disagree
/// with each other about what "world space" means.
public struct SceneNodeHierarchy: Sendable {
    private let nodesByID: [SceneNodeID: SceneNode]
    private let rootIDs: [SceneNodeID]
    private let parentIDsByChildID: [SceneNodeID: SceneNodeID]
    private let worldTransformsByID: [SceneNodeID: Transform3D]
    private let depthFirstIDs: [SceneNodeID]

    /// Builds the hierarchy of `metadata`.
    ///
    /// Fails when the tree cannot be walked — a cycle, or a child claimed by two parents — rather
    /// than skipping the offending node, because a placement computed from a partial tree would put
    /// geometry somewhere the document does not describe.
    public init(metadata: ProductMetadata) throws {
        var parentIDsByChildID: [SceneNodeID: SceneNodeID] = [:]
        for (parentID, parent) in metadata.sceneNodes {
            for childID in parent.childIDs {
                guard parentIDsByChildID[childID] == nil else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Scene node \(childID.description) is claimed by more than one parent."
                    )
                }
                parentIDsByChildID[childID] = parentID
            }
        }

        var worldTransformsByID: [SceneNodeID: Transform3D] = [:]
        var depthFirstIDs: [SceneNodeID] = []
        var visitedIDs: Set<SceneNodeID> = []
        for rootID in metadata.rootSceneNodeIDs {
            try Self.appendSubtree(
                rootID,
                parentTransform: .identity,
                metadata: metadata,
                worldTransformsByID: &worldTransformsByID,
                depthFirstIDs: &depthFirstIDs,
                visitedIDs: &visitedIDs
            )
        }

        self.nodesByID = metadata.sceneNodes
        self.rootIDs = metadata.rootSceneNodeIDs
        self.parentIDsByChildID = parentIDsByChildID
        self.worldTransformsByID = worldTransformsByID
        self.depthFirstIDs = depthFirstIDs
    }

    public func node(_ id: SceneNodeID) -> SceneNode? {
        nodesByID[id]
    }

    public func parentID(of id: SceneNodeID) -> SceneNodeID? {
        parentIDsByChildID[id]
    }

    public func isRootSceneNode(_ id: SceneNodeID) -> Bool {
        rootIDs.contains(id)
    }

    /// The transform that takes `id`'s own coordinates into world space.
    public func worldTransform(of id: SceneNodeID) throws -> Transform3D {
        guard let transform = worldTransformsByID[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node \(id.description) is not reachable from a document root."
            )
        }
        return transform
    }

    /// The transform `id`'s local transform is expressed relative to.
    public func parentWorldTransform(of id: SceneNodeID) throws -> Transform3D {
        guard let parentID = parentIDsByChildID[id] else {
            guard isRootSceneNode(id) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node \(id.description) is not reachable from a document root."
                )
            }
            return .identity
        }
        return try worldTransform(of: parentID)
    }

    /// The ancestors of `id`, nearest first.
    public func ancestorIDs(of id: SceneNodeID) -> [SceneNodeID] {
        var ancestorIDs: [SceneNodeID] = []
        var visitedIDs: Set<SceneNodeID> = [id]
        var currentID = id
        while let parentID = parentIDsByChildID[currentID], visitedIDs.insert(parentID).inserted {
            ancestorIDs.append(parentID)
            currentID = parentID
        }
        return ancestorIDs
    }

    public func isDescendant(_ id: SceneNodeID, of ancestorID: SceneNodeID) -> Bool {
        ancestorIDs(of: id).contains(ancestorID)
    }

    /// The subtree rooted at `id`, including `id`, in depth-first order.
    public func subtreeIDs(of id: SceneNodeID) -> [SceneNodeID] {
        var subtreeIDs: [SceneNodeID] = []
        var visitedIDs: Set<SceneNodeID> = []
        appendSubtreeIDs(id, subtreeIDs: &subtreeIDs, visitedIDs: &visitedIDs)
        return subtreeIDs
    }

    /// `ids` with every node that already sits below another member removed, in document order.
    ///
    /// A transform applied to both a node and its ancestor would reach the node twice. Reducing the
    /// selection to its outermost members is what makes "move everything I selected" move each piece
    /// of geometry exactly once.
    public func outermostSceneNodeIDs(among ids: [SceneNodeID]) -> [SceneNodeID] {
        let candidateIDs = Set(ids)
        let outermostIDs = candidateIDs.filter { id in
            ancestorIDs(of: id).allSatisfy { !candidateIDs.contains($0) }
        }
        return depthFirstIDs.filter { outermostIDs.contains($0) }
    }

    /// The nearest node that has every member of `ids` somewhere below it.
    ///
    /// This is where a group of those members belongs: the deepest place in the tree that can hold
    /// them all without moving any of them out from under a parent they still belong to.
    public func nearestCommonAncestorID(of ids: [SceneNodeID]) -> SceneNodeID? {
        guard let firstID = ids.first else {
            return nil
        }
        var commonChain = ancestorIDs(of: firstID)
        for id in ids.dropFirst() {
            let chain = Set(ancestorIDs(of: id))
            commonChain = commonChain.filter { chain.contains($0) }
        }
        return commonChain.first
    }

    private func appendSubtreeIDs(
        _ id: SceneNodeID,
        subtreeIDs: inout [SceneNodeID],
        visitedIDs: inout Set<SceneNodeID>
    ) {
        guard visitedIDs.insert(id).inserted,
              let node = nodesByID[id] else {
            return
        }
        subtreeIDs.append(id)
        for childID in node.childIDs {
            appendSubtreeIDs(childID, subtreeIDs: &subtreeIDs, visitedIDs: &visitedIDs)
        }
    }

    private static func appendSubtree(
        _ id: SceneNodeID,
        parentTransform: Transform3D,
        metadata: ProductMetadata,
        worldTransformsByID: inout [SceneNodeID: Transform3D],
        depthFirstIDs: inout [SceneNodeID],
        visitedIDs: inout Set<SceneNodeID>
    ) throws {
        guard visitedIDs.insert(id).inserted else {
            throw EditorError(
                code: .commandInvalid,
                message: "Scene node \(id.description) is reachable twice, so the scene tree has a cycle."
            )
        }
        guard let node = metadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node \(id.description) is referenced but missing."
            )
        }
        let worldTransform = try parentTransform.composed(with: node.localTransform)
        worldTransformsByID[id] = worldTransform
        depthFirstIDs.append(id)
        for childID in node.childIDs {
            try appendSubtree(
                childID,
                parentTransform: worldTransform,
                metadata: metadata,
                worldTransformsByID: &worldTransformsByID,
                depthFirstIDs: &depthFirstIDs,
                visitedIDs: &visitedIDs
            )
        }
    }
}
