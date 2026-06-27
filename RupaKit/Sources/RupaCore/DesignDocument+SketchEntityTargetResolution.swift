import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func editableSketchEntity(
        for target: SelectionTarget,
        operationName: String
    ) throws -> (
        featureID: FeatureID,
        entityID: SketchEntityID,
        feature: FeatureNode,
        sketch: Sketch,
        entity: SketchEntity
    ) {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch scene node."
            )
        }
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch entity selection target."
            )
        }
        guard reference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable sketch feature."
            )
        }
        guard let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an existing sketch entity."
            )
        }
        return (
            featureID: featureID,
            entityID: reference.entityID,
            feature: feature,
            sketch: sketch,
            entity: entity
        )
    }

    func editableSketchEntityBase(
        for target: SelectionTarget,
        operationName: String
    ) throws -> EditableSketchEntitySelection {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch scene node."
            )
        }
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityBaseReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch entity selection target."
            )
        }
        guard reference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable sketch feature."
            )
        }
        guard let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an existing sketch entity."
            )
        }
        return (
            featureID: featureID,
            entityID: reference.entityID,
            feature: feature,
            sketch: sketch,
            entity: entity
        )
    }
}
