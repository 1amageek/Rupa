import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Moves selected Product scene subtrees while preserving their source identity.
    ///
    /// Selection is canonicalized in document pre-order. Descendants of a
    /// selected ancestor are not moved independently. The operation stages a
    /// complete metadata value and publishes it only after validation.
    @discardableResult
    public mutating func moveSceneNodes(
        ids: [SceneNodeID],
        parentID: SceneNodeID?,
        beforeSiblingID: SceneNodeID?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> Bool {
        guard !ids.isEmpty else {
            throw sceneMoveCommandError("Scene node moves require at least one selected ID.")
        }
        guard Set(ids).count == ids.count else {
            throw sceneMoveCommandError("Scene node moves require unique selected IDs.")
        }

        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        for id in ids where productMetadata.sceneNodes[id] == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node move requires an existing scene node " + id.description + "."
            )
        }

        let selectedIDs = hierarchy.outermostSceneNodeIDs(among: ids)
        guard !selectedIDs.isEmpty else {
            throw sceneMoveCommandError("Scene node move selection did not resolve to a top-level subtree.")
        }

        var selectedSubtreeIDs: Set<SceneNodeID> = []
        for id in selectedIDs {
            selectedSubtreeIDs.formUnion(hierarchy.subtreeIDs(of: id))
        }

        let componentSourceIDs = componentDefinitionSourceSceneNodeIDs(in: productMetadata)
        for id in selectedSubtreeIDs {
            if let reason = sceneMoveOwnershipReason(
                for: id,
                metadata: productMetadata,
                componentSourceIDs: componentSourceIDs
            ) {
                throw sceneMoveCommandError(reason)
            }
            if sceneMoveNodeIsLocked(id, metadata: productMetadata) {
                throw sceneMoveCommandError("Locked scene nodes and component instances cannot be moved.")
            }
        }

        for id in selectedIDs {
            if let sourceParentID = hierarchy.parentID(of: id),
               sceneMoveNodeIsLocked(sourceParentID, metadata: productMetadata) {
                throw sceneMoveCommandError("A scene node cannot be removed from a locked parent.")
            }
        }

        if let parentID {
            guard productMetadata.sceneNodes[parentID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node move destination requires an existing parent scene node."
                )
            }
            guard !selectedSubtreeIDs.contains(parentID) else {
                throw sceneMoveCommandError("A scene node cannot be moved into itself or its descendant.")
            }
            if let reason = sceneMoveOwnershipReason(
                for: parentID,
                metadata: productMetadata,
                componentSourceIDs: componentSourceIDs
            ) {
                throw sceneMoveCommandError("Scene node move destination is source-owned: " + reason)
            }
            guard !sceneMoveNodeIsLocked(parentID, metadata: productMetadata) else {
                throw sceneMoveCommandError("A scene node cannot be moved under a locked parent.")
            }
        }

        let destinationChildren: [SceneNodeID]
        if let parentID {
            guard let destinationNode = productMetadata.sceneNodes[parentID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node move destination requires an existing parent scene node."
                )
            }
            destinationChildren = destinationNode.childIDs
        } else {
            destinationChildren = productMetadata.rootSceneNodeIDs
        }

        if let beforeSiblingID {
            guard destinationChildren.contains(beforeSiblingID) else {
                throw sceneMoveCommandError(
                    "The move anchor must be a direct child of the destination parent."
                )
            }
            guard !selectedSubtreeIDs.contains(beforeSiblingID) else {
                throw sceneMoveCommandError("The move anchor cannot belong to a moved subtree.")
            }
        }

        let destinationAfterRemoval = destinationChildren.filter {
            !selectedIDs.contains($0)
        }
        let insertionIndex: Int
        if let beforeSiblingID {
            guard let index = destinationAfterRemoval.firstIndex(of: beforeSiblingID) else {
                throw sceneMoveCommandError(
                    "The move anchor cannot be selected or removed before insertion."
                )
            }
            insertionIndex = index
        } else {
            insertionIndex = destinationAfterRemoval.count
        }
        var finalDestinationChildren = destinationAfterRemoval
        finalDestinationChildren.insert(contentsOf: selectedIDs, at: insertionIndex)

        let parentChanged = selectedIDs.contains { hierarchy.parentID(of: $0) != parentID }
        let destinationOrderChanged = finalDestinationChildren != destinationChildren
        guard parentChanged || destinationOrderChanged else {
            return false
        }

        var oldWorldByID: [SceneNodeID: Transform3D] = [:]
        var destinationWorld = Transform3D.identity
        if parentChanged {
            if let parentID {
                destinationWorld = try hierarchy.worldTransform(of: parentID)
            }
            for id in selectedIDs where hierarchy.parentID(of: id) != parentID {
                oldWorldByID[id] = try hierarchy.worldTransform(of: id)
            }
        }

        let inverseDestinationWorld = try parentChanged ? destinationWorld.inverse() : .identity
        var updatedMetadata = productMetadata

        for id in selectedIDs {
            if let sourceParentID = hierarchy.parentID(of: id) {
                guard var sourceParent = updatedMetadata.sceneNodes[sourceParentID] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Scene node move source parent is missing."
                    )
                }
                sourceParent.childIDs.removeAll { $0 == id }
                updatedMetadata.sceneNodes[sourceParentID] = sourceParent
            } else {
                updatedMetadata.rootSceneNodeIDs.removeAll { $0 == id }
            }
        }

        if let parentID {
            guard var destinationNode = updatedMetadata.sceneNodes[parentID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node move destination is missing during staging."
                )
            }
            destinationNode.childIDs = finalDestinationChildren
            updatedMetadata.sceneNodes[parentID] = destinationNode
        } else {
            updatedMetadata.rootSceneNodeIDs = finalDestinationChildren
        }

        if parentChanged {
            for id in selectedIDs where hierarchy.parentID(of: id) != parentID {
                guard let oldWorld = oldWorldByID[id] else {
                    throw sceneMoveCommandError("Scene node world placement could not be resolved.")
                }
                let local = try inverseDestinationWorld.composed(with: oldWorld)
                guard var node = updatedMetadata.sceneNodes[id] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Scene node move target is missing during staging."
                    )
                }
                try local.validateAffinePlacement()
                node.localTransform = local
                updatedMetadata.sceneNodes[id] = node
            }
        }

        try updatedMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updatedMetadata
        return true
    }
}

private func sceneMoveCommandError(_ message: String) -> EditorError {
    EditorError(code: .commandInvalid, message: message)
}

private func collectSceneMoveSubtreeIDs(
    _ id: SceneNodeID,
    metadata: ProductMetadata,
    into result: inout Set<SceneNodeID>
) {
    guard result.insert(id).inserted,
          let node = metadata.sceneNodes[id] else {
        return
    }
    for childID in node.childIDs {
        collectSceneMoveSubtreeIDs(childID, metadata: metadata, into: &result)
    }
}

private func componentDefinitionSourceSceneNodeIDs(
    in metadata: ProductMetadata
) -> Set<SceneNodeID> {
    var result: Set<SceneNodeID> = []
    for definition in metadata.componentDefinitions.values {
        for rootID in definition.rootSceneNodeIDs {
            collectSceneMoveSubtreeIDs(rootID, metadata: metadata, into: &result)
        }
    }
    return result
}

private func sceneMoveOwnershipReason(
    for id: SceneNodeID,
    metadata: ProductMetadata,
    componentSourceIDs: Set<SceneNodeID>
) -> String? {
    let patternResolver = PatternArrayOwnershipResolver()
    if patternResolver.sourceID(containingOutputSceneNode: id, in: metadata) != nil {
        return "Pattern roots and generated Pattern output scene nodes are source-owned."
    }
    if metadata.sceneNodes[id]?.reference?.constructionPlaneID != nil {
        return "Saved construction-plane scene nodes are source-owned."
    }
    if componentSourceIDs.contains(id) {
        return "Component definition source scene nodes are source-owned."
    }
    return nil
}

private func sceneMoveNodeIsLocked(
    _ id: SceneNodeID,
    metadata: ProductMetadata
) -> Bool {
    guard let node = metadata.sceneNodes[id] else {
        return false
    }
    if node.isLocked {
        return true
    }
    if let instanceID = node.reference?.componentInstanceID
        ?? node.object?.componentInstanceID,
       metadata.componentInstances[instanceID]?.isLocked == true {
        return true
    }
    return false
}
