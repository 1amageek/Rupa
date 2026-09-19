import RupaCore

struct OutlinerSourceCommandPlanner {
    static func rename(
        id: SceneNodeID,
        name: String,
        in metadata: ProductMetadata
    ) throws -> [EditorCommand] {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene node name cannot be empty."
            )
        }
        guard let node = metadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node \(id) no longer exists."
            )
        }
        let generatedIDs = OutlinerProjection.generatedOutputIDs(in: metadata)
        guard !generatedIDs.contains(id) else {
            throw EditorError(
                code: .commandUnsupported,
                message: "Generated pattern outputs are renamed through their pattern root."
            )
        }
        if let constructionPlaneID = node.reference?.constructionPlaneID {
            return [.renameConstructionPlane(id: constructionPlaneID, name: normalizedName)]
        }
        if let componentInstanceID = node.reference?.componentInstanceID
            ?? node.object?.componentInstanceID {
            return [.renameComponentInstance(id: componentInstanceID, name: normalizedName)]
        }
        if let patternSource = metadata.patternArrays.values.first(where: { $0.rootSceneNodeID == id }) {
            return [
                .updatePatternArray(
                    id: patternSource.id,
                    name: normalizedName,
                    definitionID: nil,
                    distribution: nil,
                    outputMode: nil
                )
            ]
        }
        return [.renameSceneNode(id: id, name: normalizedName)]
    }

    static func stateChange(
        ids: [SceneNodeID],
        isVisible: Bool? = nil,
        isLocked: Bool? = nil,
        in metadata: ProductMetadata
    ) throws -> [EditorCommand] {
        guard (isVisible == nil) != (isLocked == nil) else {
            throw EditorError(
                code: .commandInvalid,
                message: "An Outliner state transaction must change visibility or lock state."
            )
        }
        let orderedIDs = try orderedIDs(ids, in: metadata)
        let generatedIDs = OutlinerProjection.generatedOutputIDs(in: metadata)
        guard orderedIDs.allSatisfy({ !generatedIDs.contains($0) }) else {
            throw EditorError(
                code: .commandUnsupported,
                message: "Generated pattern outputs are controlled by their pattern root."
            )
        }
        return try orderedIDs.compactMap { id in
            guard let node = metadata.sceneNodes[id] else {
                throw missingNodeError(id)
            }
            if let isVisible, node.isVisible != isVisible {
                return .setSceneNodeVisibility(id: id, isVisible: isVisible)
            }
            if let isLocked, node.isLocked != isLocked {
                return .setSceneNodeLock(id: id, isLocked: isLocked)
            }
            return nil
        }
    }

    static func isolate(
        ids: [SceneNodeID],
        in metadata: ProductMetadata
    ) throws -> [EditorCommand] {
        let orderedIDs = try orderedIDs(ids, in: metadata)
        guard orderedIDs.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Isolate requires at least one selected scene node."
            )
        }
        let generatedIDs = OutlinerProjection.generatedOutputIDs(in: metadata)
        guard orderedIDs.allSatisfy({ !generatedIDs.contains($0) }) else {
            throw EditorError(
                code: .commandUnsupported,
                message: "Generated pattern outputs cannot be isolated individually. Select the pattern root."
            )
        }

        let allRows = OutlinerProjection.make(
            metadata: metadata,
            expandedIDs: [],
            searchText: "",
            filter: .all
        ).allRows
        let independentIDs = allRows.map(\.id).filter { !generatedIDs.contains($0) }
        let independentIDSet = Set(independentIDs)
        let parentByID = parentIDs(in: metadata)
        var visibleIDs = Set<SceneNodeID>()

        func includeSubtree(_ id: SceneNodeID) {
            guard independentIDSet.contains(id), visibleIDs.insert(id).inserted else {
                return
            }
            for childID in metadata.sceneNodes[id]?.childIDs ?? [] {
                includeSubtree(childID)
            }
        }
        for id in orderedIDs {
            includeSubtree(id)
            var parentID = parentByID[id]
            while let currentParent = parentID {
                if independentIDSet.contains(currentParent) {
                    visibleIDs.insert(currentParent)
                }
                parentID = parentByID[currentParent]
            }
        }

        return try independentIDs.compactMap { id in
            guard let node = metadata.sceneNodes[id] else {
                throw missingNodeError(id)
            }
            let shouldBeVisible = visibleIDs.contains(id)
            guard node.isVisible != shouldBeVisible else { return nil }
            return .setSceneNodeVisibility(id: id, isVisible: shouldBeVisible)
        }
    }

    static func showAll(in metadata: ProductMetadata) throws -> [EditorCommand] {
        let generatedIDs = OutlinerProjection.generatedOutputIDs(in: metadata)
        let allRows = OutlinerProjection.make(
            metadata: metadata,
            expandedIDs: [],
            searchText: "",
            filter: .all
        ).allRows
        return allRows.compactMap { row in
            guard !generatedIDs.contains(row.id),
                  let node = metadata.sceneNodes[row.id] else { return nil }
            guard !node.isVisible else { return nil }
            return .setSceneNodeVisibility(id: row.id, isVisible: true)
        }
    }

    static func validateMove(
        ids: [SceneNodeID],
        parentID: SceneNodeID?,
        beforeSiblingID: SceneNodeID?,
        in metadata: ProductMetadata
    ) throws {
        guard !ids.isEmpty, Set(ids).count == ids.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene move requires unique selected scene nodes."
            )
        }
        for id in ids {
            guard metadata.sceneNodes[id] != nil else {
                throw missingNodeError(id)
            }
        }

        let parentByID = parentIDs(in: metadata)
        let selectedSet = Set(ids)
        let generatedIDs = OutlinerProjection.generatedOutputIDs(in: metadata)
        guard selectedSet.isDisjoint(with: generatedIDs) else {
            throw EditorError(
                code: .commandUnsupported,
                message: "Generated pattern outputs cannot be moved individually."
            )
        }
        guard ids.allSatisfy({ metadata.sceneNodes[$0]?.reference?.constructionPlaneID == nil }) else {
            throw EditorError(
                code: .commandUnsupported,
                message: "Saved construction-plane nodes are moved by their owning source."
            )
        }
        guard ids.allSatisfy({ !isMoveLocked($0, metadata: metadata) }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Locked scene nodes cannot be moved."
            )
        }

        if let parentID {
            guard metadata.sceneNodes[parentID] != nil else {
                throw missingNodeError(parentID)
            }
            guard !isMoveLocked(parentID, metadata: metadata) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A locked destination cannot receive moved scene nodes."
                )
            }
            var current: SceneNodeID? = parentID
            while let currentID = current {
                guard !selectedSet.contains(currentID) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "A scene node cannot be moved into its own subtree."
                    )
                }
                current = parentByID[currentID]
            }
        }

        let destinationSiblings = parentID.flatMap { metadata.sceneNodes[$0]?.childIDs }
            ?? metadata.rootSceneNodeIDs
        if let beforeSiblingID {
            guard destinationSiblings.contains(beforeSiblingID) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "The move anchor is not a direct sibling of the destination."
                )
            }
            guard !selectedSet.contains(beforeSiblingID) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "A moved scene node cannot be its own move anchor."
                )
            }
        }
    }

    private static func orderedIDs(
        _ ids: [SceneNodeID],
        in metadata: ProductMetadata
    ) throws -> [SceneNodeID] {
        let requested = Set(ids)
        guard requested.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "The Outliner action requires at least one scene node."
            )
        }
        let ordered = OutlinerProjection.make(
            metadata: metadata,
            expandedIDs: [],
            searchText: "",
            filter: .all
        ).allRows.map(\.id)
        let resolved = Set(ordered.filter { requested.contains($0) })
        guard requested == resolved else {
            let missing = requested.subtracting(resolved).map(\.description).sorted().joined(separator: ", ")
            throw EditorError(
                code: .referenceUnresolved,
                message: "The Outliner selection contains missing scene node(s): \(missing)."
            )
        }
        return ordered.filter { requested.contains($0) }
    }

    private static func isMoveLocked(
        _ id: SceneNodeID,
        metadata: ProductMetadata
    ) -> Bool {
        guard let node = metadata.sceneNodes[id] else { return false }
        if node.isLocked { return true }
        let instanceID = node.reference?.componentInstanceID
            ?? node.object?.componentInstanceID
        return instanceID.flatMap { metadata.componentInstances[$0]?.isLocked } ?? false
    }

    private static func parentIDs(in metadata: ProductMetadata) -> [SceneNodeID: SceneNodeID] {
        var result: [SceneNodeID: SceneNodeID] = [:]
        var visited: Set<SceneNodeID> = []
        func visit(_ id: SceneNodeID) {
            guard visited.insert(id).inserted,
                  let node = metadata.sceneNodes[id] else { return }
            for childID in node.childIDs {
                result[childID] = id
                visit(childID)
            }
        }
        for rootID in metadata.rootSceneNodeIDs {
            visit(rootID)
        }
        return result
    }

    private static func missingNodeError(_ id: SceneNodeID) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "Scene node \(id) no longer exists."
        )
    }
}
