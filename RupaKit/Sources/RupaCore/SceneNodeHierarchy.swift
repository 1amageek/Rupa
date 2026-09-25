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
    public struct Occurrence: Sendable {
        public let id: SceneOccurrenceID
        public let parentID: SceneOccurrenceID?
        public let sourceSceneNodeID: SceneNodeID
        public let sceneNodeID: SceneNodeID
        public let componentInstanceID: ComponentInstanceID?
        public let localTransform: Transform3D
        public let worldTransform: Transform3D
        public let isVisible: Bool
    }

    private let componentDefinitions: [ComponentDefinitionID: ComponentDefinition]
    private let componentInstances: [ComponentInstanceID: ComponentInstance]
    private let nodesByID: [SceneNodeID: SceneNode]
    private let rootIDs: [SceneNodeID]
    private let parentIDsByChildID: [SceneNodeID: SceneNodeID]
    private let worldTransformsByID: [SceneNodeID: Transform3D]
    private let depthFirstIDs: [SceneNodeID]
    private let presentingSceneNodeIDsByFeatureID: [FeatureID: SceneNodeID]

    /// Builds the hierarchy of `metadata`.
    ///
    /// Fails when the tree cannot be walked — a cycle, or a child claimed by two parents — rather
    /// than skipping the offending node, because a placement computed from a partial tree would put
    /// geometry somewhere the document does not describe.
    public init(metadata: ProductMetadata) throws {
        guard Set(metadata.rootSceneNodeIDs).count == metadata.rootSceneNodeIDs.count else {
            throw EditorError(code: .commandInvalid, message: "Scene root IDs must be unique.")
        }
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
        let presentingSceneNodeIDsByFeatureID = try Self.presentingSceneNodeIDsByFeatureID(in: metadata)
        guard Set(metadata.rootSceneNodeIDs).isDisjoint(with: parentIDsByChildID.keys) else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene root cannot also be a child of another scene node."
            )
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
        guard Set(depthFirstIDs) == Set(metadata.sceneNodes.keys) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Every scene node must be reachable from a document root."
            )
        }

        self.componentDefinitions = metadata.componentDefinitions
        self.componentInstances = metadata.componentInstances
        self.nodesByID = metadata.sceneNodes
        self.rootIDs = metadata.rootSceneNodeIDs
        self.parentIDsByChildID = parentIDsByChildID
        self.worldTransformsByID = worldTransformsByID
        self.depthFirstIDs = depthFirstIDs
        self.presentingSceneNodeIDsByFeatureID = presentingSceneNodeIDsByFeatureID
    }

    /// The single scene node that presents `featureID`'s evaluated geometry, if any.
    ///
    /// Evaluated geometry reaches the scene only through this node and the occurrences expanded
    /// from it. A feature without a presenting node is document history, not scene content, so
    /// viewport, measurement, section and topology consumers all leave it out.
    public func presentingSceneNodeID(for featureID: FeatureID) -> SceneNodeID? {
        presentingSceneNodeIDsByFeatureID[featureID]
    }

    /// The occurrences among `occurrences` that place `featureID`'s evaluated geometry.
    public func presentationOccurrences(
        of featureID: FeatureID,
        in occurrences: [Occurrence]
    ) -> [Occurrence] {
        guard let sceneNodeID = presentingSceneNodeIDsByFeatureID[featureID] else {
            return []
        }
        return occurrences.filter { $0.sourceSceneNodeID == sceneNodeID }
    }

    /// Indexes feature presentations and rejects a feature presented by more than one node.
    ///
    /// A second presenting node would give one piece of evaluated geometry two unrelated
    /// placements, and topology, measurement and section results could not name which one they
    /// describe. Repetition belongs to component instances, which expand into distinct occurrences.
    static func presentingSceneNodeIDsByFeatureID(
        in metadata: ProductMetadata
    ) throws -> [FeatureID: SceneNodeID] {
        let index = FeaturePresentationIndex(sceneNodes: metadata.sceneNodes)
        if let conflict = index.conflict {
            throw EditorError(code: .commandInvalid, message: conflict.message)
        }
        return index.sceneNodeIDsByFeatureID
    }

    public func resolvedOccurrences() throws -> [Occurrence] {
        var result: [Occurrence] = []
        for rootID in rootIDs {
            try appendOccurrences(
                rootID, prefix: nil, parentID: nil, parentTransform: .identity,
                localPrefix: .identity, ownerID: nil, instanceID: nil,
                isVisible: true, definitionPath: [], result: &result
            )
        }
        return result
    }

    private func appendOccurrences(
        _ nodeID: SceneNodeID,
        prefix: String?,
        parentID: SceneOccurrenceID?,
        parentTransform: Transform3D,
        localPrefix: Transform3D,
        ownerID: SceneNodeID?,
        instanceID: ComponentInstanceID?,
        isVisible: Bool,
        definitionPath: Set<ComponentDefinitionID>,
        result: inout [Occurrence]
    ) throws {
        try Task.checkCancellation()
        guard let node = nodesByID[nodeID] else {
            throw EditorError(code: .referenceUnresolved, message: "Component source scene node is missing.")
        }
        let id = SceneOccurrenceID(rawValue: prefix.map { "\($0)/\(nodeID.description)" }
            ?? "scene.\(nodeID.description)")
        let local = try localPrefix.composed(with: node.localTransform)
        let world = try parentTransform.composed(with: local)
        let visible = isVisible && node.isVisible
        result.append(Occurrence(
            id: id, parentID: parentID, sourceSceneNodeID: nodeID,
            sceneNodeID: ownerID ?? nodeID, componentInstanceID: instanceID,
            localTransform: local, worldTransform: world, isVisible: visible
        ))
        if node.reference?.kind == .componentInstance {
            guard let childInstanceID = node.reference?.componentInstanceID,
                  let instance = componentInstances[childInstanceID],
                  let definition = componentDefinitions[instance.definitionID] else {
                throw EditorError(code: .referenceUnresolved, message: "Component occurrence requires its instance and definition.")
            }
            guard !definitionPath.contains(definition.id) else {
                throw EditorError(code: .commandInvalid, message: "Component definitions must not contain recursive instances.")
            }
            try instance.localTransform.validateAffinePlacement()
            var path = definitionPath
            path.insert(definition.id)
            for rootID in definition.rootSceneNodeIDs {
                try appendOccurrences(
                    rootID, prefix: id.rawValue, parentID: id, parentTransform: world,
                    localPrefix: instance.localTransform, ownerID: ownerID ?? nodeID,
                    instanceID: instanceID ?? childInstanceID,
                    isVisible: visible && instance.isVisible, definitionPath: path, result: &result
                )
            }
        }
        for childID in node.childIDs {
            try appendOccurrences(
                childID, prefix: prefix == nil ? nil : id.rawValue,
                parentID: id, parentTransform: world, localPrefix: .identity,
                ownerID: ownerID, instanceID: instanceID, isVisible: visible,
                definitionPath: definitionPath, result: &result
            )
        }
    }

    public func node(_ id: SceneNodeID) -> SceneNode? {
        nodesByID[id]
    }

    /// Scene nodes in document depth-first order.
    public var orderedSceneNodeIDs: [SceneNodeID] {
        depthFirstIDs
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
        try Task.checkCancellation()
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
        try node.localTransform.validateAffinePlacement()
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
