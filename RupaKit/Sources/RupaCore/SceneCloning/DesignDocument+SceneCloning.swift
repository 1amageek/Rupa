import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// A self-contained copy of `ids` in world placement, for transport to this or another document.
    public func sceneFragment(copying ids: [SceneNodeID]) throws -> SceneFragment {
        try SceneFragmentExtractor().extract(
            rootSceneNodeIDs: ids,
            frame: .world,
            metadata: productMetadata,
            cadDocument: cadDocument,
            authoredMeshAssets: authoredMeshAssets
        )
    }

    /// Copies `ids` in place, as siblings right after them, and returns the copied roots.
    @discardableResult
    public mutating func duplicateSceneNodes(
        ids: [SceneNodeID],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        try placeSceneNodes(ids: ids, placements: [.identity], boolean: nil, objectRegistry: objectRegistry)
    }

    /// Places `ids` once per world-space placement of the selection and returns the new roots:
    /// independent copies beside the selection, or instances of the selection's component
    /// definition that show it at the same placements.
    @discardableResult
    public mutating func placeSceneNodes(
        ids: [SceneNodeID],
        placements: [Transform3D],
        output: SceneNodePlacementOutput = .independentCopy,
        boolean: SceneNodePlacementBoolean? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        if output == .componentInstance {
            guard boolean == nil else {
                throw EditorError(code: .commandInvalid, message: "Only independent copies can be combined with a Boolean.")
            }
            return try placeInstances(of: ids, placements: placements, objectRegistry: objectRegistry)
        }
        let fragment = try sceneFragment(copying: ids)
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        let firstRootID = fragment.roots[0].sceneNodeID
        let rootIDs = Set(fragment.roots.map(\.sceneNodeID))
        let destination: SceneFragmentInserter.Attachment
        let parentWorld: Transform3D
        if let parentID = hierarchy.parentID(of: firstRootID), let parent = productMetadata.sceneNodes[parentID] {
            let lastIndex = parent.childIDs.lastIndex { rootIDs.contains($0) } ?? (parent.childIDs.count - 1)
            destination = .child(of: parentID, at: lastIndex + 1)
            parentWorld = try hierarchy.worldTransform(of: parentID)
        } else {
            destination = .documentRoot
            parentWorld = .identity
        }
        return try insertCopies(
            of: fragment,
            placements: placements,
            destination: destination,
            parentWorld: parentWorld,
            boolean: boolean,
            objectRegistry: objectRegistry
        )
    }

    /// Inserts one copy of `fragment` per world-space placement under the first document root and
    /// returns the copied roots.
    @discardableResult
    public mutating func pasteSceneFragment(
        _ fragment: SceneFragment,
        placements: [Transform3D],
        boolean: SceneNodePlacementBoolean? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        let destination: SceneFragmentInserter.Attachment
        let parentWorld: Transform3D
        if let rootID = productMetadata.rootSceneNodeIDs.first, let root = productMetadata.sceneNodes[rootID] {
            destination = .child(of: rootID, at: root.childIDs.count)
            parentWorld = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: rootID)
        } else {
            destination = .documentRoot
            parentWorld = .identity
        }
        return try insertCopies(
            of: fragment,
            placements: placements,
            destination: destination,
            parentWorld: parentWorld,
            boolean: boolean,
            objectRegistry: objectRegistry
        )
    }

    /// Realize Instances: each selected component instance node becomes an independent copy of its
    /// definition where the instance shows it, beside the instance, and the instance is removed.
    /// The definition and its other instances are untouched. Returns the copied roots.
    ///
    /// An instance shows a definition root at W(instance node) ∘ L(instance) ∘ L(root), while the
    /// root itself sits at W(root's parent) ∘ L(root); the copy is therefore placed by
    /// W(instance node) ∘ L(instance) ∘ W(root's parent)⁻¹.
    @discardableResult
    public mutating func realizeComponentInstances(
        sceneNodeIDs ids: [SceneNodeID],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        guard !ids.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Realize Instances takes component instances.")
        }
        var updated = self
        var realized: [SceneNodeID] = []
        for id in ids {
            guard let node = updated.productMetadata.sceneNodes[id],
                  node.reference?.kind == .componentInstance,
                  let instanceID = node.reference?.componentInstanceID,
                  let instance = updated.productMetadata.componentInstances[instanceID],
                  let definition = updated.productMetadata.componentDefinitions[instance.definitionID],
                  let firstRoot = definition.rootSceneNodeIDs.first else {
                throw EditorError(code: .commandInvalid, message: "Realize Instances takes component instances.")
            }
            let hierarchy = try SceneNodeHierarchy(metadata: updated.productMetadata)
            let placement = try hierarchy.worldTransform(of: id)
                .composed(with: instance.localTransform)
                .composed(with: try hierarchy.parentWorldTransform(of: firstRoot).inverse())
            let fragment = try updated.sceneFragment(copying: definition.rootSceneNodeIDs)
            let destination: SceneFragmentInserter.Attachment
            let parentWorld: Transform3D
            if let parentID = hierarchy.parentID(of: id), let parent = updated.productMetadata.sceneNodes[parentID] {
                destination = .child(of: parentID, at: (parent.childIDs.firstIndex(of: id) ?? parent.childIDs.count - 1) + 1)
                parentWorld = try hierarchy.worldTransform(of: parentID)
            } else {
                destination = .documentRoot
                parentWorld = .identity
            }
            realized += try updated.insertCopies(
                of: fragment, placements: [placement], destination: destination,
                parentWorld: parentWorld, boolean: nil, objectRegistry: objectRegistry
            )
            try updated.deleteSceneNodes(ids: [id], objectRegistry: objectRegistry)
        }
        self = updated
        return realized
    }

    private mutating func placeInstances(
        of ids: [SceneNodeID],
        placements: [Transform3D],
        objectRegistry: ObjectTypeRegistry
    ) throws -> [SceneNodeID] {
        if let refusal = productMetadata.sceneCopyRefusal(for: ids) {
            throw refusal
        }
        guard !placements.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Placing instances requires at least one placement.")
        }
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        let roots = hierarchy.outermostSceneNodeIDs(among: ids)
        guard Set(roots.map { hierarchy.parentID(of: $0) }).count == 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Instances keep one placement frame; place objects under one parent together."
            )
        }
        // An instance shows its definition roots in the definition's own frame, so the instance
        // transform carries the roots' parent frame to reproduce their world placement.
        let parentWorld = try hierarchy.parentWorldTransform(of: roots[0])
        guard let documentRootID = productMetadata.rootSceneNodeIDs.first else {
            throw EditorError(code: .commandInvalid, message: "Placing instances requires a document root.")
        }
        let inverseInstanceParent = try hierarchy.worldTransform(of: documentRootID).inverse()

        var updated = self
        let definitionID: ComponentDefinitionID
        if let existing = updated.productMetadata.componentDefinitions.values.first(where: {
            Set($0.rootSceneNodeIDs) == Set(roots)
        }) {
            definitionID = existing.id
        } else {
            let base = "\(productMetadata.sceneNodes[roots[0]]?.name ?? "Object") Source"
            let taken = Set(updated.productMetadata.componentDefinitions.values.map(\.name))
            var name = base
            var ordinal = 2
            while taken.contains(name) {
                name = "\(base) \(ordinal)"
                ordinal += 1
            }
            definitionID = try updated.createComponentDefinition(
                name: name, rootSceneNodeIDs: roots, objectRegistry: objectRegistry
            )
        }
        let definitionName = updated.productMetadata.componentDefinitions[definitionID]?.name ?? "Instance"
        var instanceNodeIDs: [SceneNodeID] = []
        for placement in placements {
            try placement.validateAffinePlacement()
            let taken = Set(updated.productMetadata.componentInstances.values.map(\.name))
            var ordinal = 1
            while taken.contains("\(definitionName) \(ordinal)") {
                ordinal += 1
            }
            let instanceID = try updated.createComponentInstance(
                name: "\(definitionName) \(ordinal)",
                definitionID: definitionID,
                localTransform: try inverseInstanceParent.composed(with: try placement.composed(with: parentWorld)),
                objectRegistry: objectRegistry
            )
            guard let nodeID = updated.productMetadata.sceneNodes.values.first(where: {
                $0.reference?.componentInstanceID == instanceID
            })?.id else {
                throw EditorError(code: .referenceUnresolved, message: "A placed instance has no scene node.")
            }
            instanceNodeIDs.append(nodeID)
        }
        self = updated
        return instanceNodeIDs
    }

    private mutating func insertCopies(
        of fragment: SceneFragment,
        placements: [Transform3D],
        destination: SceneFragmentInserter.Attachment,
        parentWorld: Transform3D,
        boolean: SceneNodePlacementBoolean?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [SceneNodeID] {
        guard !placements.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Placing copies requires at least one placement.")
        }
        var metadata = productMetadata
        var document = cadDocument
        var meshAssets = authoredMeshAssets
        var copiedRootIDs: [SceneNodeID] = []
        var copiesByPlacement: [[SceneNodeID]] = []
        var nextDestination = destination
        for placement in placements {
            try placement.validateAffinePlacement()
            let insertion = try SceneFragmentInserter().insert(
                fragment,
                placement: placement,
                parentWorld: parentWorld,
                attachment: nextDestination,
                naming: .copy,
                metadata: &metadata,
                cadDocument: &document,
                authoredMeshAssets: &meshAssets
            )
            copiedRootIDs.append(contentsOf: insertion.rootSceneNodeIDs)
            copiesByPlacement.append(insertion.sceneNodeIDs)
            // Later copies follow earlier ones among the same siblings.
            if case .child(let parentID, let index) = nextDestination {
                nextDestination = .child(of: parentID, at: index + insertion.rootSceneNodeIDs.count)
            }
        }
        try document.validate(tolerance: .standard)
        try metadata.validate(against: document, objectRegistry: objectRegistry)
        var updated = self
        updated.cadDocument = document
        updated.productMetadata = metadata
        updated.authoredMeshAssets = meshAssets
        if let boolean {
            try updated.combinePlacedCopies(copiesByPlacement, rootIDs: copiedRootIDs, with: boolean, objectRegistry: objectRegistry)
        }
        self = updated
        return copiedRootIDs
    }

    /// Combines each placed copy with the body it was placed on, in placement order: the copy's one
    /// body is the tool, the first copy combines with the target and every later copy with the
    /// previous result. The consumed copies are hidden.
    private mutating func combinePlacedCopies(
        _ copiesByPlacement: [[SceneNodeID]],
        rootIDs: [SceneNodeID],
        with boolean: SceneNodePlacementBoolean,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let targetNode = productMetadata.sceneNodes[boolean.targetSceneNodeID],
              let reference = targetNode.reference,
              reference.kind == .body || reference.kind == .feature,
              var targetFeatureID = reference.featureID else {
            throw EditorError(code: .referenceUnresolved, message: "A placement Boolean needs a body to combine with.")
        }
        for copiedNodeIDs in copiesByPlacement {
            let toolFeatureIDs = copiedNodeIDs.compactMap { id -> FeatureID? in
                guard let node = productMetadata.sceneNodes[id], node.isVisible,
                      node.reference?.kind == .body else { return nil }
                return node.reference?.featureID
            }
            guard toolFeatureIDs.count == 1, let toolFeatureID = toolFeatureIDs.first else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A placement Boolean needs the placed objects to be exactly one body."
                )
            }
            targetFeatureID = try createBoolean(
                name: "Placed \(boolean.operation.rawValue.capitalized)",
                targets: [BooleanTargetReference(featureID: targetFeatureID)],
                tool: BooleanToolReference(featureID: toolFeatureID),
                operation: boolean.operation,
                keepTools: false,
                objectRegistry: objectRegistry
            )
        }
        for rootID in rootIDs {
            productMetadata.sceneNodes[rootID]?.isVisible = false
        }
    }
}
