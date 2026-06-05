import Foundation
import RupaCore

public struct AutomationRunner {
    public init() {}

    public func execute(
        _ command: AutomationCommand,
        in session: EditorSession
    ) throws -> AutomationResult {
        switch command {
        case .describeDocument:
            return AutomationResult(
                message: "Document uses \(session.document.displayUnit.symbol) display units.",
                generation: session.generation,
                diagnostics: session.diagnostics
            )
        case .setDisplayUnit(let unit):
            let result = try session.execute(.setDisplayUnit(unit))
            return AutomationResult(
                message: "Display unit changed to \(unit.symbol).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .renameDocument(let name):
            let result = try session.execute(.renameDocument(name: name))
            return AutomationResult(
                message: "Document renamed to \(name).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .upsertParameter(let name, let expression, let kind):
            let result = try session.execute(
                .upsertParameter(
                    name: name,
                    expression: expression,
                    kind: kind
                )
            )
            return AutomationResult(
                message: "Parameter \(name) updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .deleteParameter(let name):
            let result = try session.execute(.deleteParameter(name: name))
            return AutomationResult(
                message: "Parameter \(name) deleted.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createComponentDefinition(let name, let rootSceneNodeIDs):
            let result = try session.execute(
                .createComponentDefinition(
                    name: name,
                    rootSceneNodeIDs: rootSceneNodeIDs
                )
            )
            return AutomationResult(
                message: "Component definition \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createComponentInstance(let name, let definitionID, let localTransform):
            let result = try session.execute(
                .createComponentInstance(
                    name: name,
                    definitionID: definitionID,
                    localTransform: localTransform
                )
            )
            return AutomationResult(
                message: "Component instance \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSceneNodeVisibility(let id, let isVisible):
            let result = try session.execute(
                .setSceneNodeVisibility(id: id, isVisible: isVisible)
            )
            return AutomationResult(
                message: "Scene node visibility updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSceneNodeLock(let id, let isLocked):
            let result = try session.execute(
                .setSceneNodeLock(id: id, isLocked: isLocked)
            )
            return AutomationResult(
                message: "Scene node lock updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSceneNodeTransform(let id, let localTransform):
            let result = try session.execute(
                .setSceneNodeTransform(
                    id: id,
                    localTransform: localTransform
                )
            )
            return AutomationResult(
                message: "Scene node transform updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setComponentInstanceVisibility(let id, let isVisible):
            let result = try session.execute(
                .setComponentInstanceVisibility(id: id, isVisible: isVisible)
            )
            return AutomationResult(
                message: "Component instance visibility updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setComponentInstanceLock(let id, let isLocked):
            let result = try session.execute(
                .setComponentInstanceLock(id: id, isLocked: isLocked)
            )
            return AutomationResult(
                message: "Component instance lock updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setComponentInstanceTransform(let id, let localTransform):
            let result = try session.execute(
                .setComponentInstanceTransform(
                    id: id,
                    localTransform: localTransform
                )
            )
            return AutomationResult(
                message: "Component instance transform updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createSectionPlane(let name):
            let result = try session.execute(.createSectionPlane(name: name))
            return AutomationResult(
                message: "Section plane \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createLineSketch(let name, let plane, let start, let end):
            let result = try session.execute(
                .createLineSketch(
                    name: name,
                    plane: plane,
                    start: start,
                    end: end
                )
            )
            return AutomationResult(
                message: "Line sketch \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createCircleSketch(let name, let plane, let center, let radius):
            let result = try session.execute(
                .createCircleSketch(
                    name: name,
                    plane: plane,
                    center: center,
                    radius: radius
                )
            )
            return AutomationResult(
                message: "Circle sketch \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createRectangleSketch(let name, let plane, let width, let height):
            let result = try session.execute(
                .createRectangleSketch(
                    name: name,
                    plane: plane,
                    width: width,
                    height: height
                )
            )
            return AutomationResult(
                message: "Rectangle sketch \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .addSketchConstraint(let featureID, let constraint):
            let result = try session.execute(
                .addSketchConstraint(
                    featureID: featureID,
                    constraint: constraint
                )
            )
            return AutomationResult(
                message: "Sketch constraint added to \(featureID.description).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .extrudeProfile(let name, let profile, let distance, let direction):
            let result = try session.execute(
                .extrudeProfile(
                    name: name,
                    profile: profile,
                    distance: distance,
                    direction: direction
                )
            )
            return AutomationResult(
                message: "Profile extrude \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createExtrudedRectangle(let name, let plane, let width, let height, let depth, let direction):
            let result = try session.execute(
                .createExtrudedRectangle(
                    name: name,
                    plane: plane,
                    width: width,
                    height: height,
                    depth: depth,
                    direction: direction
                )
            )
            return AutomationResult(
                message: "Extruded rectangle \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createExtrudedRectangleFromCorners(
            let name,
            let plane,
            let firstCorner,
            let oppositeCorner,
            let depth,
            let direction
        ):
            let result = try session.execute(
                .createExtrudedRectangleFromCorners(
                    name: name,
                    plane: plane,
                    firstCorner: firstCorner,
                    oppositeCorner: oppositeCorner,
                    depth: depth,
                    direction: direction
                )
            )
            return AutomationResult(
                message: "Extruded rectangle \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createExtrudedCircle(let name, let plane, let center, let radius, let depth, let direction):
            let result = try session.execute(
                .createExtrudedCircle(
                    name: name,
                    plane: plane,
                    center: center,
                    radius: radius,
                    depth: depth,
                    direction: direction
                )
            )
            return AutomationResult(
                message: "Extruded circle \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .validateDocument:
            let result = try session.execute(.validateDocument)
            return AutomationResult(
                message: "Validation finished.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        }
    }

    public func executeBatch(
        _ batch: AutomationBatch,
        in session: EditorSession
    ) throws -> [AutomationResult] {
        try session.store.requireGeneration(batch.expectedGeneration)
        var results: [AutomationResult] = []
        for command in batch.commands {
            results.append(try execute(command, in: session))
        }
        return results
    }
}
