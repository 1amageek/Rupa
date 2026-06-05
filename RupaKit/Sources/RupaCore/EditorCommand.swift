import Foundation
import SwiftCAD

public enum EditorCommand: Codable, Equatable, Sendable {
    case setDisplayUnit(LengthDisplayUnit)
    case setRulerConfiguration(RulerConfiguration)
    case renameDocument(name: String)
    case resetDocument(name: String)
    case replaceProductMetadata(ProductMetadata)
    case upsertParameter(name: String, expression: CADExpression, kind: QuantityKind)
    case deleteParameter(name: String)
    case createComponentDefinition(name: String, rootSceneNodeIDs: [SceneNodeID])
    case createComponentInstance(
        name: String,
        definitionID: ComponentDefinitionID,
        localTransform: Transform3D
    )
    case setSceneNodeVisibility(id: SceneNodeID, isVisible: Bool)
    case setSceneNodeLock(id: SceneNodeID, isLocked: Bool)
    case setSceneNodeTransform(id: SceneNodeID, localTransform: Transform3D)
    case setSceneNodeMaterial(id: SceneNodeID, materialID: MaterialID?)
    case setSceneNodeObjectProperty(id: SceneNodeID, propertyID: ObjectPropertyID, value: ObjectPropertyValue?)
    case setComponentInstanceVisibility(id: ComponentInstanceID, isVisible: Bool)
    case setComponentInstanceLock(id: ComponentInstanceID, isLocked: Bool)
    case setComponentInstanceTransform(id: ComponentInstanceID, localTransform: Transform3D)
    case createSectionPlane(name: String)
    case createLineSketch(name: String, plane: SketchPlane, start: SketchPoint, end: SketchPoint)
    case createCircleSketch(name: String, plane: SketchPlane, center: SketchPoint, radius: CADExpression)
    case createRectangleSketch(name: String, plane: SketchPlane, width: CADExpression, height: CADExpression)
    case addSketchConstraint(featureID: FeatureID, constraint: SketchConstraint)
    case createRectangleSketchFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    )
    case setExtrudeDistance(featureID: FeatureID, distance: CADExpression)
    case setCubeDimensions(
        featureID: FeatureID,
        sizeX: CADExpression,
        sizeY: CADExpression,
        sizeZ: CADExpression
    )
    case setCylinderDimensions(
        featureID: FeatureID,
        radius: CADExpression,
        sizeY: CADExpression
    )
    case extrudeProfile(name: String, profile: ProfileReference, distance: CADExpression, direction: ExtrudeDirection)
    case createExtrudedRectangle(
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case createExtrudedRectangleFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case createExtrudedCircle(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection
    )
    case validateDocument

    public var name: String {
        switch self {
        case .setDisplayUnit:
            "setDisplayUnit"
        case .setRulerConfiguration:
            "setRulerConfiguration"
        case .renameDocument:
            "renameDocument"
        case .resetDocument:
            "resetDocument"
        case .replaceProductMetadata:
            "replaceProductMetadata"
        case .upsertParameter:
            "upsertParameter"
        case .deleteParameter:
            "deleteParameter"
        case .createComponentDefinition:
            "createComponentDefinition"
        case .createComponentInstance:
            "createComponentInstance"
        case .setSceneNodeVisibility:
            "setSceneNodeVisibility"
        case .setSceneNodeLock:
            "setSceneNodeLock"
        case .setSceneNodeTransform:
            "setSceneNodeTransform"
        case .setSceneNodeMaterial:
            "setSceneNodeMaterial"
        case .setSceneNodeObjectProperty:
            "setSceneNodeObjectProperty"
        case .setComponentInstanceVisibility:
            "setComponentInstanceVisibility"
        case .setComponentInstanceLock:
            "setComponentInstanceLock"
        case .setComponentInstanceTransform:
            "setComponentInstanceTransform"
        case .createSectionPlane:
            "createSectionPlane"
        case .createLineSketch:
            "createLineSketch"
        case .createCircleSketch:
            "createCircleSketch"
        case .createRectangleSketch:
            "createRectangleSketch"
        case .addSketchConstraint:
            "addSketchConstraint"
        case .createRectangleSketchFromCorners:
            "createRectangleSketchFromCorners"
        case .setExtrudeDistance:
            "setExtrudeDistance"
        case .setCubeDimensions:
            "setCubeDimensions"
        case .setCylinderDimensions:
            "setCylinderDimensions"
        case .extrudeProfile:
            "extrudeProfile"
        case .createExtrudedRectangle:
            "createExtrudedRectangle"
        case .createExtrudedRectangleFromCorners:
            "createExtrudedRectangleFromCorners"
        case .createExtrudedCircle:
            "createExtrudedCircle"
        case .validateDocument:
            "validateDocument"
        }
    }

    public var mutatesDocument: Bool {
        switch self {
        case .setDisplayUnit,
             .setRulerConfiguration,
             .renameDocument,
             .resetDocument,
             .replaceProductMetadata,
             .upsertParameter,
             .deleteParameter,
             .createComponentDefinition,
             .createComponentInstance,
             .setSceneNodeVisibility,
             .setSceneNodeLock,
             .setSceneNodeTransform,
             .setSceneNodeMaterial,
             .setSceneNodeObjectProperty,
             .setComponentInstanceVisibility,
             .setComponentInstanceLock,
             .setComponentInstanceTransform,
             .createSectionPlane,
             .createLineSketch,
             .createCircleSketch,
             .createRectangleSketch,
             .addSketchConstraint,
             .createRectangleSketchFromCorners,
             .setExtrudeDistance,
             .setCubeDimensions,
             .setCylinderDimensions,
             .extrudeProfile,
             .createExtrudedRectangle,
             .createExtrudedRectangleFromCorners,
             .createExtrudedCircle:
            true
        case .validateDocument:
            false
        }
    }
}
