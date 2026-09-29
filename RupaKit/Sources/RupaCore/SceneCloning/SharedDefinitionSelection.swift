import SwiftCAD

/// The geometry edited once for a definition and every scene placement affected by that edit.
public struct SharedDefinitionSelection: Sendable {
    public let definitionID: ComponentDefinitionID
    public let name: String
    public let contentNodeIDs: [SceneNodeID]
    public let placementNodeIDs: [SceneNodeID]

    public init(definitionID: ComponentDefinitionID, metadata: ProductMetadata) throws {
        guard let definition = metadata.componentDefinitions[definitionID] else {
            throw EditorError(code: .referenceUnresolved, message: "The shared definition no longer exists.")
        }
        let content = try Self.content(of: definition, in: metadata)
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        let placements = Self.placements(
            of: [(definition, content)], hierarchy: hierarchy, occurrences: try hierarchy.resolvedOccurrences()
        )
        self.init(definition: definition, content: content, placements: placements[0])
    }

    private init(definition: ComponentDefinition, content: [SceneNodeID], placements: [SceneNodeID]) {
        definitionID = definition.id
        name = definition.name
        contentNodeIDs = content
        placementNodeIDs = placements
    }

    /// Every definition's selection from one scene hierarchy and one pass over its occurrences,
    /// where building each on its own rebuilt both once per definition. A definition whose content
    /// cannot be walked (a missing node, a recursive instance) fails alone.
    public static func all(
        in metadata: ProductMetadata
    ) throws -> [ComponentDefinitionID: Result<SharedDefinitionSelection, any Error>] {
        var results: [ComponentDefinitionID: Result<SharedDefinitionSelection, any Error>] = [:]
        var walked: [(ComponentDefinition, [SceneNodeID])] = []
        for definition in metadata.componentDefinitions.values {
            do {
                walked.append((definition, try content(of: definition, in: metadata)))
            } catch {
                results[definition.id] = .failure(error)
            }
        }
        guard !walked.isEmpty else { return results }
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        let placements = placements(of: walked, hierarchy: hierarchy, occurrences: try hierarchy.resolvedOccurrences())
        for (index, (definition, content)) in walked.enumerated() {
            results[definition.id] = .success(Self(definition: definition, content: content, placements: placements[index]))
        }
        return results
    }

    /// The definition's geometry nodes, through nested instances, in walk order.
    private static func content(of definition: ComponentDefinition, in metadata: ProductMetadata) throws -> [SceneNodeID] {
        var content: [SceneNodeID] = []
        var visited = Set<SceneNodeID>()
        func collect(_ id: SceneNodeID, definitions: Set<ComponentDefinitionID>) throws {
            guard let node = metadata.sceneNodes[id] else {
                throw EditorError(code: .referenceUnresolved, message: "Shared definition content is missing.")
            }
            if let instanceID = node.reference?.componentInstanceID {
                guard let instance = metadata.componentInstances[instanceID],
                      let nested = metadata.componentDefinitions[instance.definitionID],
                      !definitions.contains(nested.id) else {
                    throw EditorError(code: .commandInvalid, message: "A shared definition contains a missing or recursive instance.")
                }
                for root in nested.rootSceneNodeIDs {
                    try collect(root, definitions: definitions.union([nested.id]))
                }
            }
            guard visited.insert(id).inserted else { return }
            if node.reference?.featureID != nil || node.reference?.kind == .authoredMesh {
                content.append(id)
                return
            }
            for child in node.childIDs { try collect(child, definitions: definitions) }
        }
        for root in definition.rootSceneNodeIDs { try collect(root, definitions: [definition.id]) }
        return content
    }

    /// Each definition's placements, in occurrence order: an instance's owning node, or the direct
    /// root that holds a directly presented content node. One pass over the occurrences serves
    /// every definition.
    private static func placements(
        of definitions: [(ComponentDefinition, [SceneNodeID])],
        hierarchy: SceneNodeHierarchy,
        occurrences: [SceneNodeHierarchy.Occurrence]
    ) -> [[SceneNodeID]] {
        var owners: [SceneNodeID: [Int]] = [:]
        var directRootByContent: [[SceneNodeID: SceneNodeID]] = []
        for (index, (definition, content)) in definitions.enumerated() {
            let contentIDs = Set(content)
            for id in contentIDs { owners[id, default: []].append(index) }
            var directRoots: [SceneNodeID: SceneNodeID] = [:]
            for root in definition.rootSceneNodeIDs {
                for id in hierarchy.subtreeIDs(of: root) where contentIDs.contains(id) {
                    directRoots[id] = root
                }
            }
            directRootByContent.append(directRoots)
        }
        var placements = Array(repeating: [SceneNodeID](), count: definitions.count)
        var seen = Array(repeating: Set<SceneNodeID>(), count: definitions.count)
        for occurrence in occurrences {
            guard let indices = owners[occurrence.sourceSceneNodeID] else { continue }
            for index in indices {
                let placementID = occurrence.componentInstanceID == nil
                    ? (directRootByContent[index][occurrence.sourceSceneNodeID] ?? occurrence.sceneNodeID)
                    : occurrence.sceneNodeID
                if seen[index].insert(placementID).inserted { placements[index].append(placementID) }
            }
        }
        return placements
    }
}
