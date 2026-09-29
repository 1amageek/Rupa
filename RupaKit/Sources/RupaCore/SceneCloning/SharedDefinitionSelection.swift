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
        for root in definition.rootSceneNodeIDs { try collect(root, definitions: [definitionID]) }
        let contentIDs = Set(content)
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        var directRootByContent: [SceneNodeID: SceneNodeID] = [:]
        for root in definition.rootSceneNodeIDs {
            for id in hierarchy.subtreeIDs(of: root) where contentIDs.contains(id) {
                directRootByContent[id] = root
            }
        }
        var placements: [SceneNodeID] = []
        var seen = Set<SceneNodeID>()
        for occurrence in try hierarchy.resolvedOccurrences() where contentIDs.contains(occurrence.sourceSceneNodeID) {
            let placementID = occurrence.componentInstanceID == nil
                ? (directRootByContent[occurrence.sourceSceneNodeID] ?? occurrence.sceneNodeID)
                : occurrence.sceneNodeID
            if seen.insert(placementID).inserted { placements.append(placementID) }
        }
        self.definitionID = definitionID
        self.name = definition.name
        self.contentNodeIDs = content
        self.placementNodeIDs = placements
    }
}
