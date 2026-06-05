import Foundation
import SwiftCAD

public enum EditorCommand: Codable, Equatable, Sendable {
    case setDisplayUnit(LengthDisplayUnit)
    case setRulerConfiguration(RulerConfiguration)
    case renameDocument(name: String)
    case resetDocument(name: String)
    case replaceProductMetadata(RupaProductMetadata)
    case upsertParameter(name: String, expression: CADExpression, kind: QuantityKind)
    case deleteParameter(name: String)
    case createComponentDefinition(name: String, rootSceneNodeIDs: [RupaSceneNodeID])
    case createComponentInstance(
        name: String,
        definitionID: RupaComponentDefinitionID,
        localTransform: Transform3D
    )
    case setSceneNodeVisibility(id: RupaSceneNodeID, isVisible: Bool)
    case setSceneNodeLock(id: RupaSceneNodeID, isLocked: Bool)
    case setSceneNodeTransform(id: RupaSceneNodeID, localTransform: Transform3D)
    case setSceneNodeMaterial(id: RupaSceneNodeID, materialID: MaterialID?)
    case setComponentInstanceVisibility(id: RupaComponentInstanceID, isVisible: Bool)
    case setComponentInstanceLock(id: RupaComponentInstanceID, isLocked: Bool)
    case setComponentInstanceTransform(id: RupaComponentInstanceID, localTransform: Transform3D)
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
