import RupaCore
import RupaViewportScene

/// Parent world frames for the document's scene nodes, resolved once per
/// overlay frame for the transform gizmos that commit against them.
///
/// The walk is these routes' own rather than the shared scene transform index,
/// because that index answers a missing node and a non-representable product
/// with an identity frame. A gizmo commits `P⁻¹ · M_w · P · L`, so an identity
/// substituted for `P` would commit a frame nobody authored.
/// Every answer here is therefore a resolved frame, a typed refusal, or a
/// documented absence the caller reads as "this node names no commit target".
package struct ViewportSceneNodeParentFrames: Sendable {
    /// The frame a node inherits from its ancestors, carried down the walk.
    private enum Inherited {
        case frame(Transform3D)
        case refused(String)
    }

    private var frames: [SceneNodeID: Transform3D] = [:]
    private var refusals: [SceneNodeID: String] = [:]
    private var collisions: Set<SceneNodeID> = []

    /// Walks the scene tree top down from `rootSceneNodeIDs`.
    ///
    /// A node reached a second time makes the tree ill-formed at that node, so
    /// it is recorded as a collision and not descended into again. That bounds
    /// the walk by the node count and makes a cycle terminate as a refusal
    /// rather than a hang. A subtree whose ancestor product is not
    /// representable inherits the refusal instead of disappearing, so the
    /// absence of a frame always means "not in the tree" and never "the walk
    /// gave up here".
    package init(document: DesignDocument) throws {
        let nodes = document.productMetadata.sceneNodes
        var visited = Set<SceneNodeID>()
        var stack: [(id: SceneNodeID, inherited: Inherited)] = document.productMetadata
            .rootSceneNodeIDs
            .reversed()
            .map { ($0, .frame(.identity)) }
        while let entry = stack.popLast() {
            try Task.checkCancellation()
            guard visited.insert(entry.id).inserted else {
                collisions.insert(entry.id)
                continue
            }
            let node = nodes[entry.id]
            let inheritedByChildren: Inherited
            switch entry.inherited {
            case .frame(let parentWorld):
                frames[entry.id] = parentWorld
                guard let node else { continue }
                do {
                    inheritedByChildren = .frame(
                        try ViewportWorldTransformAlgebra.multiplied(parentWorld, node.localTransform)
                    )
                } catch {
                    inheritedByChildren = .refused(
                        "An ancestor scene node frame of this sketch is not representable."
                    )
                }
            case .refused(let reason):
                refusals[entry.id] = reason
                guard node != nil else { continue }
                inheritedByChildren = entry.inherited
            }
            guard let node else { continue }
            for childID in node.childIDs {
                stack.append((childID, inheritedByChildren))
            }
        }
    }

    /// The world frame the node's own local transform is applied within.
    ///
    /// Returns `nil` when the node is not part of the document's scene tree at
    /// all; the caller draws that sketch's outline and no handles, because
    /// there is no scene node for a commit to address.
    package func parentWorldTransform(of sceneNodeID: SceneNodeID) throws -> Transform3D? {
        guard !collisions.contains(sceneNodeID) else {
            throw RealityViewportSpatialBatch.invalid(
                "A scene node appears more than once in the scene tree, so its sketch transform has no single parent frame."
            )
        }
        if let reason = refusals[sceneNodeID] {
            throw RealityViewportSpatialBatch.invalid(reason)
        }
        return frames[sceneNodeID]
    }
}
