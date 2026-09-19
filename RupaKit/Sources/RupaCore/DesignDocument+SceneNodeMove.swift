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

        let hierarchy = try SceneMoveHierarchy(metadata: productMetadata)
        let requestedIDs = Set(ids)
        for id in ids where productMetadata.sceneNodes[id] == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node move requires an existing scene node " + id.description + "."
            )
        }

        let selectedIDs = hierarchy.preorder.filter { id in
            guard requestedIDs.contains(id) else {
                return false
            }
            var ancestorID = hierarchy.parentByID[id]
            while let candidate = ancestorID {
                if requestedIDs.contains(candidate) {
                    return false
                }
                ancestorID = hierarchy.parentByID[candidate]
            }
            return true
        }
        guard !selectedIDs.isEmpty else {
            throw sceneMoveCommandError("Scene node move selection did not resolve to a top-level subtree.")
        }

        var selectedSubtreeIDs: Set<SceneNodeID> = []
        for id in selectedIDs {
            collectSceneMoveSubtreeIDs(
                id,
                metadata: productMetadata,
                into: &selectedSubtreeIDs
            )
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
            if let sourceParentID = hierarchy.parentByID[id],
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

        let parentChanged = selectedIDs.contains { hierarchy.parentByID[$0] != parentID }
        let destinationOrderChanged = finalDestinationChildren != destinationChildren
        guard parentChanged || destinationOrderChanged else {
            return false
        }

        var oldWorldByID: [SceneNodeID: SceneMoveMatrix] = [:]
        var destinationWorld = SceneMoveMatrix.identity
        if parentChanged {
            if let parentID {
                destinationWorld = try sceneMoveWorldMatrix(
                    for: parentID,
                    metadata: productMetadata,
                    parentByID: hierarchy.parentByID,
                    cache: &oldWorldByID
                )
            }
            for id in selectedIDs where hierarchy.parentByID[id] != parentID {
                oldWorldByID[id] = try sceneMoveWorldMatrix(
                    for: id,
                    metadata: productMetadata,
                    parentByID: hierarchy.parentByID,
                    cache: &oldWorldByID
                )
            }
        }

        let inverseDestinationWorld = try parentChanged
            ? destinationWorld.inverted()
            : SceneMoveMatrix.identity
        var updatedMetadata = productMetadata

        for id in selectedIDs {
            if let sourceParentID = hierarchy.parentByID[id] {
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
            for id in selectedIDs where hierarchy.parentByID[id] != parentID {
                guard let oldWorld = oldWorldByID[id] else {
                    throw sceneMoveCommandError("Scene node world placement could not be resolved.")
                }
                let local = try inverseDestinationWorld.multiplied(by: oldWorld)
                guard var node = updatedMetadata.sceneNodes[id] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Scene node move target is missing during staging."
                    )
                }
                node.localTransform = Transform3D(
                    matrix: try Matrix4x4(values: local.values)
                )
                updatedMetadata.sceneNodes[id] = node
            }
        }

        try updatedMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updatedMetadata
        return true
    }
}

private struct SceneMoveHierarchy {
    let preorder: [SceneNodeID]
    let parentByID: [SceneNodeID: SceneNodeID]

    init(metadata: ProductMetadata) throws {
        guard !metadata.rootSceneNodeIDs.isEmpty else {
            throw sceneMoveCommandError("Scene node moves require a non-empty root list.")
        }
        guard Set(metadata.rootSceneNodeIDs).count == metadata.rootSceneNodeIDs.count else {
            throw sceneMoveCommandError("Scene node root IDs must be unique.")
        }

        var preorder: [SceneNodeID] = []
        preorder.reserveCapacity(metadata.sceneNodes.count)
        var visited: Set<SceneNodeID> = []
        var visiting: Set<SceneNodeID> = []
        var parentByID: [SceneNodeID: SceneNodeID] = [:]

        func visit(_ id: SceneNodeID, parent: SceneNodeID?) throws {
            guard metadata.sceneNodes[id] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node hierarchy references a missing scene node."
                )
            }
            guard !visiting.contains(id) else {
                throw sceneMoveCommandError("Scene node hierarchy contains a cycle.")
            }
            if visited.contains(id) {
                if let parent,
                   parentByID[id] != parent {
                    throw sceneMoveCommandError("Scene node hierarchy contains multiple parents.")
                }
                return
            }

            visiting.insert(id)
            guard let node = metadata.sceneNodes[id] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node hierarchy references a missing scene node."
                )
            }
            guard Set(node.childIDs).count == node.childIDs.count else {
                throw sceneMoveCommandError("Scene node hierarchy contains a duplicate child ID.")
            }
            if let parent {
                if parentByID[id] != nil {
                    throw sceneMoveCommandError("Scene node hierarchy contains multiple parents.")
                }
                parentByID[id] = parent
            }
            preorder.append(id)
            for childID in node.childIDs {
                try visit(childID, parent: id)
            }
            visiting.remove(id)
            visited.insert(id)
        }

        for rootID in metadata.rootSceneNodeIDs {
            try visit(rootID, parent: nil)
        }
        guard visited == Set(metadata.sceneNodes.keys) else {
            throw sceneMoveCommandError("Every scene node must be reachable from the root list.")
        }
        guard Set(metadata.rootSceneNodeIDs).isDisjoint(with: parentByID.keys) else {
            throw sceneMoveCommandError("A root scene node cannot also be a child scene node.")
        }

        self.preorder = preorder
        self.parentByID = parentByID
    }
}

private struct SceneMoveMatrix {
    static let identity = SceneMoveMatrix(uncheckedValues: [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ])

    let values: [Double]

    init(values: [Double], owner: String) throws {
        guard values.count == 16, values.allSatisfy(\.isFinite) else {
            throw sceneMoveCommandError(owner + " placement matrix must contain 16 finite values.")
        }
        guard values[12] == 0.0,
              values[13] == 0.0,
              values[14] == 0.0,
              values[15] == 1.0 else {
            throw sceneMoveCommandError(owner + " placement matrix must be affine.")
        }
        guard Self.determinant3x3(values) != 0.0 else {
            throw sceneMoveCommandError(owner + " placement matrix must be invertible.")
        }
        self.values = values
    }

    private init(uncheckedValues values: [Double]) {
        self.values = values
    }

    func multiplied(by other: SceneMoveMatrix) throws -> SceneMoveMatrix {
        var result = Array(repeating: 0.0, count: 16)
        for row in 0..<4 {
            for column in 0..<4 {
                var value = 0.0
                for index in 0..<4 {
                    value += values[row * 4 + index] * other.values[index * 4 + column]
                }
                result[row * 4 + column] = value
            }
        }
        return try SceneMoveMatrix(values: result, owner: "Scene node")
    }

    func inverted() throws -> SceneMoveMatrix {
        let a = values[0]
        let b = values[1]
        let c = values[2]
        let d = values[4]
        let e = values[5]
        let f = values[6]
        let g = values[8]
        let h = values[9]
        let i = values[10]
        let determinant = Self.determinant3x3(values)
        guard determinant != 0.0, determinant.isFinite else {
            throw sceneMoveCommandError("Destination placement matrix must be invertible.")
        }

        let inverse00 = (e * i - f * h) / determinant
        let inverse01 = (c * h - b * i) / determinant
        let inverse02 = (b * f - c * e) / determinant
        let inverse10 = (f * g - d * i) / determinant
        let inverse11 = (a * i - c * g) / determinant
        let inverse12 = (c * d - a * f) / determinant
        let inverse20 = (d * h - e * g) / determinant
        let inverse21 = (b * g - a * h) / determinant
        let inverse22 = (a * e - b * d) / determinant
        let translationX = values[3]
        let translationY = values[7]
        let translationZ = values[11]
        let inverseTranslationX = -(
            inverse00 * translationX
                + inverse01 * translationY
                + inverse02 * translationZ
        )
        let inverseTranslationY = -(
            inverse10 * translationX
                + inverse11 * translationY
                + inverse12 * translationZ
        )
        let inverseTranslationZ = -(
            inverse20 * translationX
                + inverse21 * translationY
                + inverse22 * translationZ
        )
        return try SceneMoveMatrix(
            values: [
                inverse00, inverse01, inverse02, inverseTranslationX,
                inverse10, inverse11, inverse12, inverseTranslationY,
                inverse20, inverse21, inverse22, inverseTranslationZ,
                0.0, 0.0, 0.0, 1.0,
            ],
            owner: "Destination"
        )
    }

    private static func determinant3x3(_ values: [Double]) -> Double {
        values[0] * (values[5] * values[10] - values[6] * values[9])
            - values[1] * (values[4] * values[10] - values[6] * values[8])
            + values[2] * (values[4] * values[9] - values[5] * values[8])
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

private func sceneMoveWorldMatrix(
    for id: SceneNodeID,
    metadata: ProductMetadata,
    parentByID: [SceneNodeID: SceneNodeID],
    cache: inout [SceneNodeID: SceneMoveMatrix]
) throws -> SceneMoveMatrix {
    if let cached = cache[id] {
        return cached
    }
    guard let node = metadata.sceneNodes[id] else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Scene node world placement requires an existing scene node."
        )
    }
    let local = try SceneMoveMatrix(values: node.localTransform.matrix.values, owner: "Scene node")
    let world: SceneMoveMatrix
    if let parentID = parentByID[id] {
        let parentWorld = try sceneMoveWorldMatrix(
            for: parentID,
            metadata: metadata,
            parentByID: parentByID,
            cache: &cache
        )
        world = try parentWorld.multiplied(by: local)
    } else {
        world = local
    }
    cache[id] = world
    return world
}
