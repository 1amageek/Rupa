import Foundation
import SwiftCAD
import RupaCoreTypes

struct DesignDisplayComponentResolver {
    func curveCurvatureComponentID(
        for target: SelectionTarget,
        in document: DesignDocument
    ) throws -> SelectionComponentID {
        let selection = try sketchEntitySelection(
            for: target,
            in: document,
            operationName: "Curve curvature display",
            missingSceneNodeMessage: "Curve curvature display requires a sketch scene node.",
            missingTargetMessage: "Curve curvature display requires a sketch curve selection target.",
            missingEntityMessage: "Curve curvature display requires an existing sketch entity."
        )
        switch selection.entity {
        case .line,
             .circle,
             .arc,
             .spline:
            return .sketchEntity(
                featureID: selection.featureID,
                entityID: selection.entityID
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Curve curvature display requires a source curve entity, not a point."
            )
        }
    }

    func pointComponentID(
        for target: SelectionTarget,
        in document: DesignDocument
    ) throws -> SelectionComponentID {
        let selection = try sketchEntitySelection(
            for: target,
            in: document,
            operationName: "Point display",
            missingSceneNodeMessage: "Point display requires a sketch scene node.",
            missingTargetMessage: "Point display requires a sketch curve, point handle, or control point selection target.",
            missingEntityMessage: "Point display requires an existing sketch entity."
        )
        switch selection.entity {
        case .line,
             .circle,
             .arc,
             .spline:
            return .sketchEntity(
                featureID: selection.featureID,
                entityID: selection.entityID
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Point display requires a source curve entity, not a standalone point."
            )
        }
    }

    private func sketchEntitySelection(
        for target: SelectionTarget,
        in document: DesignDocument,
        operationName: String,
        missingSceneNodeMessage: String,
        missingTargetMessage: String,
        missingEntityMessage: String
    ) throws -> (
        featureID: FeatureID,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) {
        guard let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: missingSceneNodeMessage
            )
        }
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityBaseReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: missingTargetMessage
            )
        }
        guard reference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: missingEntityMessage
            )
        }
        return (
            featureID: featureID,
            entityID: reference.entityID,
            entity: entity
        )
    }
}
