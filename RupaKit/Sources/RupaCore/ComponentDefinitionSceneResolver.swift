import Foundation
import SwiftCAD

public struct ComponentDefinitionSceneResolver: Sendable {
    public init() {}

    public func bodySceneNodeIDs(
        in definition: ComponentDefinition,
        preferredFeatureID: FeatureID?,
        metadata: ProductMetadata
    ) -> [SceneNodeID] {
        var bodySceneNodeIDs: [SceneNodeID] = []
        var visitedSceneNodeIDs: Set<SceneNodeID> = []
        var visitedDefinitionIDs: Set<ComponentDefinitionID> = [definition.id]
        for rootSceneNodeID in definition.rootSceneNodeIDs {
            appendBodySceneNodeIDs(
                rootSceneNodeID,
                preferredFeatureID: preferredFeatureID,
                metadata: metadata,
                bodySceneNodeIDs: &bodySceneNodeIDs,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs
            )
        }
        return bodySceneNodeIDs
    }

    public func containsRenderableSceneNode(
        in definition: ComponentDefinition,
        metadata: ProductMetadata
    ) -> Bool {
        var visitedSceneNodeIDs: Set<SceneNodeID> = []
        var visitedDefinitionIDs: Set<ComponentDefinitionID> = [definition.id]
        for rootSceneNodeID in definition.rootSceneNodeIDs {
            if sceneNodeTreeContainsRenderableNode(
                rootSceneNodeID,
                metadata: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs
            ) {
                return true
            }
        }
        return false
    }

    private func appendBodySceneNodeIDs(
        _ sceneNodeID: SceneNodeID,
        preferredFeatureID: FeatureID?,
        metadata: ProductMetadata,
        bodySceneNodeIDs: inout [SceneNodeID],
        visitedSceneNodeIDs: inout Set<SceneNodeID>,
        visitedDefinitionIDs: inout Set<ComponentDefinitionID>
    ) {
        guard visitedSceneNodeIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        if sceneNode.reference?.kind == .body,
           let featureID = sceneNode.reference?.featureID,
           preferredFeatureID == nil || preferredFeatureID == featureID {
            bodySceneNodeIDs.append(sceneNodeID)
        }
        appendNestedComponentDefinitionBodySceneNodeIDs(
            from: sceneNode,
            preferredFeatureID: preferredFeatureID,
            metadata: metadata,
            bodySceneNodeIDs: &bodySceneNodeIDs,
            visitedSceneNodeIDs: &visitedSceneNodeIDs,
            visitedDefinitionIDs: &visitedDefinitionIDs
        )
        for childID in sceneNode.childIDs {
            appendBodySceneNodeIDs(
                childID,
                preferredFeatureID: preferredFeatureID,
                metadata: metadata,
                bodySceneNodeIDs: &bodySceneNodeIDs,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs
            )
        }
    }

    private func appendNestedComponentDefinitionBodySceneNodeIDs(
        from sceneNode: SceneNode,
        preferredFeatureID: FeatureID?,
        metadata: ProductMetadata,
        bodySceneNodeIDs: inout [SceneNodeID],
        visitedSceneNodeIDs: inout Set<SceneNodeID>,
        visitedDefinitionIDs: inout Set<ComponentDefinitionID>
    ) {
        guard sceneNode.reference?.kind == .componentInstance,
              let componentInstanceID = sceneNode.reference?.componentInstanceID,
              let instance = metadata.componentInstances[componentInstanceID],
              let definition = metadata.componentDefinitions[instance.definitionID],
              visitedDefinitionIDs.insert(definition.id).inserted else {
            return
        }
        for rootSceneNodeID in definition.rootSceneNodeIDs {
            appendBodySceneNodeIDs(
                rootSceneNodeID,
                preferredFeatureID: preferredFeatureID,
                metadata: metadata,
                bodySceneNodeIDs: &bodySceneNodeIDs,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs
            )
        }
    }

    private func sceneNodeTreeContainsRenderableNode(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        visitedSceneNodeIDs: inout Set<SceneNodeID>,
        visitedDefinitionIDs: inout Set<ComponentDefinitionID>
    ) -> Bool {
        guard visitedSceneNodeIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return false
        }
        if let reference = sceneNode.reference {
            switch reference.kind {
            case .body, .sketch:
                return true
            case .componentInstance:
                if nestedComponentInstanceContainsRenderableNode(
                    sceneNode,
                    metadata: metadata,
                    visitedSceneNodeIDs: &visitedSceneNodeIDs,
                    visitedDefinitionIDs: &visitedDefinitionIDs
                ) {
                    return true
                }
            case .feature, .construction:
                break
            }
        }
        for childID in sceneNode.childIDs {
            if sceneNodeTreeContainsRenderableNode(
                childID,
                metadata: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs
            ) {
                return true
            }
        }
        return false
    }

    private func nestedComponentInstanceContainsRenderableNode(
        _ sceneNode: SceneNode,
        metadata: ProductMetadata,
        visitedSceneNodeIDs: inout Set<SceneNodeID>,
        visitedDefinitionIDs: inout Set<ComponentDefinitionID>
    ) -> Bool {
        guard let componentInstanceID = sceneNode.reference?.componentInstanceID,
              let instance = metadata.componentInstances[componentInstanceID],
              let definition = metadata.componentDefinitions[instance.definitionID],
              visitedDefinitionIDs.insert(definition.id).inserted else {
            return false
        }
        for rootSceneNodeID in definition.rootSceneNodeIDs {
            if sceneNodeTreeContainsRenderableNode(
                rootSceneNodeID,
                metadata: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs,
                visitedDefinitionIDs: &visitedDefinitionIDs
            ) {
                return true
            }
        }
        return false
    }
}
