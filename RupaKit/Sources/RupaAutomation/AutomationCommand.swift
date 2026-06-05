import Foundation
import RupaCore
import SwiftCAD

public enum AutomationCommand: Codable, Equatable, Sendable {
    case describeDocument
    case setDisplayUnit(LengthDisplayUnit)
    case renameDocument(name: String)
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
    case setComponentInstanceVisibility(id: RupaComponentInstanceID, isVisible: Bool)
    case setComponentInstanceLock(id: RupaComponentInstanceID, isLocked: Bool)
    case setComponentInstanceTransform(id: RupaComponentInstanceID, localTransform: Transform3D)
    case createSectionPlane(name: String)
    case createLineSketch(name: String, plane: SketchPlane, start: SketchPoint, end: SketchPoint)
    case createCircleSketch(name: String, plane: SketchPlane, center: SketchPoint, radius: CADExpression)
    case createRectangleSketch(name: String, plane: SketchPlane, width: CADExpression, height: CADExpression)
    case addSketchConstraint(featureID: FeatureID, constraint: SketchConstraint)
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

    public var editorCommand: EditorCommand? {
        switch self {
        case .describeDocument:
            nil
        case .setDisplayUnit(let unit):
            .setDisplayUnit(unit)
        case .renameDocument(let name):
            .renameDocument(name: name)
        case .upsertParameter(let name, let expression, let kind):
            .upsertParameter(
                name: name,
                expression: expression,
                kind: kind
            )
        case .deleteParameter(let name):
            .deleteParameter(name: name)
        case .createComponentDefinition(let name, let rootSceneNodeIDs):
            .createComponentDefinition(
                name: name,
                rootSceneNodeIDs: rootSceneNodeIDs
            )
        case .createComponentInstance(let name, let definitionID, let localTransform):
            .createComponentInstance(
                name: name,
                definitionID: definitionID,
                localTransform: localTransform
            )
        case .setSceneNodeVisibility(let id, let isVisible):
            .setSceneNodeVisibility(id: id, isVisible: isVisible)
        case .setSceneNodeLock(let id, let isLocked):
            .setSceneNodeLock(id: id, isLocked: isLocked)
        case .setSceneNodeTransform(let id, let localTransform):
            .setSceneNodeTransform(
                id: id,
                localTransform: localTransform
            )
        case .setComponentInstanceVisibility(let id, let isVisible):
            .setComponentInstanceVisibility(id: id, isVisible: isVisible)
        case .setComponentInstanceLock(let id, let isLocked):
            .setComponentInstanceLock(id: id, isLocked: isLocked)
        case .setComponentInstanceTransform(let id, let localTransform):
            .setComponentInstanceTransform(
                id: id,
                localTransform: localTransform
            )
        case .createSectionPlane(let name):
            .createSectionPlane(name: name)
        case .createLineSketch(let name, let plane, let start, let end):
            .createLineSketch(
                name: name,
                plane: plane,
                start: start,
                end: end
            )
        case .createCircleSketch(let name, let plane, let center, let radius):
            .createCircleSketch(
                name: name,
                plane: plane,
                center: center,
                radius: radius
            )
        case .createRectangleSketch(let name, let plane, let width, let height):
            .createRectangleSketch(
                name: name,
                plane: plane,
                width: width,
                height: height
            )
        case .addSketchConstraint(let featureID, let constraint):
            .addSketchConstraint(
                featureID: featureID,
                constraint: constraint
            )
        case .extrudeProfile(let name, let profile, let distance, let direction):
            .extrudeProfile(
                name: name,
                profile: profile,
                distance: distance,
                direction: direction
            )
        case .createExtrudedRectangle(let name, let plane, let width, let height, let depth, let direction):
            .createExtrudedRectangle(
                name: name,
                plane: plane,
                width: width,
                height: height,
                depth: depth,
                direction: direction
            )
        case .createExtrudedRectangleFromCorners(
            let name,
            let plane,
            let firstCorner,
            let oppositeCorner,
            let depth,
            let direction
        ):
            .createExtrudedRectangleFromCorners(
                name: name,
                plane: plane,
                firstCorner: firstCorner,
                oppositeCorner: oppositeCorner,
                depth: depth,
                direction: direction
            )
        case .createExtrudedCircle(let name, let plane, let center, let radius, let depth, let direction):
            .createExtrudedCircle(
                name: name,
                plane: plane,
                center: center,
                radius: radius,
                depth: depth,
                direction: direction
            )
        case .validateDocument:
            .validateDocument
        }
    }
}
