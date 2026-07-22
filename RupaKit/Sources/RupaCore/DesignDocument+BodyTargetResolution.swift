import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    struct EditableBodyTargetResolution {
        var sceneNodeID: SceneNodeID
        var sceneNode: SceneNode
        var featureID: FeatureID
        var target: SelectionTarget
    }

    func editableBodyTargetResolution(
        for target: SelectionTarget,
        operationName: String
    ) throws -> EditableBodyTargetResolution {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              let reference = sceneNode.reference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body scene node."
            )
        }
        if reference.kind == .body,
           let featureID = reference.featureID {
            return EditableBodyTargetResolution(
                sceneNodeID: target.sceneNodeID,
                sceneNode: sceneNode,
                featureID: featureID,
                target: target
            )
        }
        guard reference.kind == .componentInstance,
              let componentInstanceID = reference.componentInstanceID,
              let instance = productMetadata.componentInstances[componentInstanceID],
              let definition = productMetadata.componentDefinitions[instance.definitionID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body scene node."
            )
        }
        let preferredFeatureID = try sourceFeatureID(
            for: target.component,
            operationName: operationName
        )
        let bodySceneNodeIDs = ComponentDefinitionSceneResolver().bodySceneNodeIDs(
            in: definition,
            preferredFeatureID: preferredFeatureID,
            metadata: productMetadata
        )
        guard let sourceSceneNodeID = bodySceneNodeIDs.first,
              bodySceneNodeIDs.count == 1,
              let sourceSceneNode = productMetadata.sceneNodes[sourceSceneNodeID],
              let sourceFeatureID = sourceSceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) component instance target must resolve to exactly one source body scene node."
            )
        }
        return EditableBodyTargetResolution(
            sceneNodeID: sourceSceneNodeID,
            sceneNode: sourceSceneNode,
            featureID: sourceFeatureID,
            target: SelectionTarget(
                sceneNodeID: sourceSceneNodeID,
                component: target.component
            )
        )
    }

    private func sourceFeatureID(
        for component: SelectionComponent,
        operationName: String
    ) throws -> FeatureID? {
        let componentID: SelectionComponentID?
        switch component {
        case .face(let id), .edge(let id), .vertex(let id):
            componentID = id
        case .object, .sketchEntity, .region, .constructionPlane:
            componentID = nil
        }
        guard let componentID,
              componentID.isStableTopology else {
            return nil
        }
        let reference = try StableTopologyReferenceParser().parse(
            componentID,
            operationName: operationName
        )
        return reference.subshapeID.featureID
    }
}
