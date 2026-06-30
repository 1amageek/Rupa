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
        case .createPatternArray(let name, let definitionID, let distribution, let outputMode):
            let result = try session.execute(
                .createPatternArray(
                    name: name,
                    definitionID: definitionID,
                    distribution: distribution,
                    outputMode: outputMode
                )
            )
            return AutomationResult(
                message: "Pattern array \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .updatePatternArray(let id, let name, let definitionID, let distribution, let outputMode):
            let result = try session.execute(
                .updatePatternArray(
                    id: id,
                    name: name,
                    definitionID: definitionID,
                    distribution: distribution,
                    outputMode: outputMode
                )
            )
            return AutomationResult(
                message: "Pattern array updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .explodePatternArray(let id):
            let result = try session.execute(.explodePatternArray(id: id))
            return AutomationResult(
                message: "Pattern array exploded.",
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
        case .describeConstructionPlanes:
            let summary = ConstructionPlaneSummaryService().summarize(
                document: session.document
            )
            let activeName = summary.planes.first { $0.isActive }?.name ?? "none"
            return AutomationResult(
                message: "\(summary.planes.count) construction plane(s). Active: \(activeName).",
                generation: session.generation,
                diagnostics: session.diagnostics
            )
        case .createConstructionPlane(let name, let plane, let activates):
            let result = try session.execute(
                .createConstructionPlane(
                    name: name,
                    plane: plane,
                    activates: activates
                )
            )
            return AutomationResult(
                message: "Construction plane \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createConstructionPlaneFromTarget(let name, let target, let activates):
            let result = try session.execute(
                .createConstructionPlaneFromTarget(
                    name: name,
                    target: target,
                    activates: activates
                )
            )
            return AutomationResult(
                message: "Construction plane \(name) created from target \(target.component).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createConstructionPlaneFromTargets(let name, let targets, let viewNormal, let activates):
            let result = try session.execute(
                .createConstructionPlaneFromTargets(
                    name: name,
                    targets: targets,
                    viewNormal: viewNormal,
                    activates: activates
                )
            )
            return AutomationResult(
                message: "Construction plane \(name) created from \(targets.count) targets.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createViewAlignedConstructionPlane(let name, let origin, let viewNormal, let activates):
            let result = try session.execute(
                .createViewAlignedConstructionPlane(
                    name: name,
                    origin: origin,
                    viewNormal: viewNormal,
                    activates: activates
                )
            )
            return AutomationResult(
                message: "View-aligned construction plane \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setActiveConstructionPlane(let id):
            let result = try session.execute(.setActiveConstructionPlane(id: id))
            let activeName = session.activeConstructionPlane?.name ?? "none"
            return AutomationResult(
                message: "Active construction plane set to \(activeName).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .renameConstructionPlane(let id, let name):
            let result = try session.execute(.renameConstructionPlane(id: id, name: name))
            let renamedName = session.document.productMetadata.constructionPlanes[id]?.name ?? name
            return AutomationResult(
                message: "Construction plane renamed to \(renamedName).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setCurveCurvatureDisplay(let target, let isVisible, let combScale):
            let result = try session.execute(
                .setCurveCurvatureDisplay(
                    target: target,
                    isVisible: isVisible,
                    combScale: combScale
                )
            )
            let visibility = isVisible.map { $0 ? "enabled" : "disabled" } ?? "toggled"
            let scale = combScale.map { " at comb scale \($0)" } ?? ""
            return AutomationResult(
                message: "Curve curvature display \(visibility)\(scale).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setPointDisplay(let target, let isVisible):
            let result = try session.execute(
                .setPointDisplay(target: target, isVisible: isVisible)
            )
            let visibility = isVisible.map { $0 ? "visible" : "hidden" } ?? "toggled"
            return AutomationResult(
                message: "Point display \(visibility).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceControlPointDisplay(let target, let isVisible):
            let result = try session.execute(
                .setSurfaceControlPointDisplay(target: target, isVisible: isVisible)
            )
            let visibility = isVisible.map { $0 ? "visible" : "hidden" } ?? "toggled"
            return AutomationResult(
                message: "Surface control point display \(visibility).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createSketch(let name, let sketch, let geometryRole):
            let result = try session.execute(
                .createSketch(
                    name: name,
                    sketch: sketch,
                    geometryRole: geometryRole
                )
            )
            let entityLabel = sketch.entities.count == 1 ? "entity" : "entities"
            return AutomationResult(
                message: "Sketch \(name) created with \(sketch.entities.count) \(entityLabel).",
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
        case .createArcSketch(let name, let plane, let center, let radius, let startAngle, let endAngle):
            let result = try session.execute(
                .createArcSketch(
                    name: name,
                    plane: plane,
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
            )
            return AutomationResult(
                message: "Arc sketch \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createSplineSketch(let name, let plane, let spline):
            let result = try session.execute(
                .createSplineSketch(
                    name: name,
                    plane: plane,
                    spline: spline
                )
            )
            return AutomationResult(
                message: "Spline sketch \(name) created.",
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
        case .createPolygonSketch(
            let name,
            let plane,
            let center,
            let radius,
            let sides,
            let sizingMode,
            let inclinationMode,
            let rotationAngle
        ):
            let result = try session.execute(
                .createPolygonSketch(
                    name: name,
                    plane: plane,
                    center: center,
                    radius: radius,
                    sides: sides,
                    sizingMode: sizingMode,
                    inclinationMode: inclinationMode,
                    rotationAngle: rotationAngle
                )
            )
            return AutomationResult(
                message: "Polygon sketch \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createFaceKnife(let name, let target, let loop):
            let result = try session.execute(
                .createFaceKnife(
                    name: name,
                    target: target,
                    loop: loop
                )
            )
            return AutomationResult(
                message: "Face Knife \(name) applied.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .projectSketchCurvesToConstructionPlane(let targets, let plane, let name):
            let result = try session.execute(
                .projectSketchCurvesToConstructionPlane(
                    targets: targets,
                    plane: plane,
                    name: name
                )
            )
            return AutomationResult(
                message: "Sketch curves projected.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .projectCurvesToGeneratedFace(let targets, let face, let name):
            let result = try session.execute(
                .projectCurvesToGeneratedFace(
                    targets: targets,
                    face: face,
                    name: name
                )
            )
            return AutomationResult(
                message: "Curves projected to generated face.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .projectBodyOutlinesToConstructionPlane(let targets, let plane, let name):
            let result = try session.execute(
                .projectBodyOutlinesToConstructionPlane(
                    targets: targets,
                    plane: plane,
                    name: name
                )
            )
            return AutomationResult(
                message: "Body outlines projected.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setObjectDimension(let target, let kind, let value):
            let result = try session.execute(
                .setObjectDimension(
                    target: target,
                    kind: kind,
                    value: value
                )
            )
            return AutomationResult(
                message: "Object dimension updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .addSelectionDimension(let name, let kind, let first, let second, let target):
            let result = try session.execute(
                .addSelectionDimension(
                    name: name,
                    kind: kind,
                    first: first,
                    second: second,
                    target: target
                )
            )
            return AutomationResult(
                message: "Selection dimension added.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics,
                addedSelectionDimensionID: result.addedSelectionDimensionID
            )
        case .setSelectionDimensionTarget(let id, let target):
            let result = try session.execute(
                .setSelectionDimensionTarget(
                    id: id,
                    target: target
                )
            )
            return AutomationResult(
                message: "Selection dimension target updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .applySelectionDimensionTarget(let id):
            let result = try session.execute(.applySelectionDimensionTarget(id: id))
            return AutomationResult(
                message: "Selection dimension target applied.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .removeSelectionDimension(let id):
            let result = try session.execute(.removeSelectionDimension(id: id))
            return AutomationResult(
                message: "Selection dimension removed.",
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
        case .removeSketchConstraint(let featureID, let constraint):
            let result = try session.execute(
                .removeSketchConstraint(
                    featureID: featureID,
                    constraint: constraint
                )
            )
            return AutomationResult(
                message: "Sketch constraint removed from \(featureID.description).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createBridgeCurve(let featureID, let firstEndpoint, let secondEndpoint, let continuity, let trimsSourceCurves):
            let result = try session.execute(
                .createBridgeCurve(
                    featureID: featureID,
                    firstEndpoint: firstEndpoint,
                    secondEndpoint: secondEndpoint,
                    continuity: continuity,
                    trimsSourceCurves: trimsSourceCurves
                )
            )
            return AutomationResult(
                message: "Bridge curve created in sketch \(featureID.description).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setBridgeCurveParameters(let sourceID, let firstEndpoint, let secondEndpoint, let continuity, let trimsSourceCurves):
            let result = try session.execute(
                .setBridgeCurveParameters(
                    sourceID: sourceID,
                    firstEndpoint: firstEndpoint,
                    secondEndpoint: secondEndpoint,
                    continuity: continuity,
                    trimsSourceCurves: trimsSourceCurves
                )
            )
            return AutomationResult(
                message: "Bridge curve \(sourceID.description) updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .offsetCurve(let target, let distance, let options, let vertexHandle):
            let result = try session.execute(
                .offsetCurve(
                    target: target,
                    distance: distance,
                    options: options,
                    vertexHandle: vertexHandle
                )
            )
            let message: String
            if options.mode == .slot {
                message = "Slot sketch profile created."
            } else if vertexHandle == nil {
                message = "Sketch curve offset created."
            } else {
                message = "Sketch vertex offset created."
            }
            return AutomationResult(
                message: message,
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .offsetRegions(let targets, let distance, let options, let combinesRegions):
            let result = try session.execute(
                .offsetRegions(
                    targets: targets,
                    distance: distance,
                    options: options,
                    combinesRegions: combinesRegions
                )
            )
            return AutomationResult(
                message: combinesRegions ? "Combined sketch regions offset created." : "Sketch regions offset created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .offsetSketchVertex(let target, let handle, let distance):
            let result = try session.execute(
                .offsetSketchVertex(
                    target: target,
                    handle: handle,
                    distance: distance
                )
            )
            return AutomationResult(
                message: "Sketch vertex offset created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .applySketchCornerTreatment(let target, let adjacentTarget, let distance, let treatment):
            let result = try session.execute(
                .applySketchCornerTreatment(
                    target: target,
                    adjacentTarget: adjacentTarget,
                    distance: distance,
                    treatment: treatment
                )
            )
            return AutomationResult(
                message: sketchCornerTreatmentAutomationMessage(treatment),
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createSlotSketch(let target, let width):
            let result = try session.execute(
                .createSlotSketch(
                    target: target,
                    width: width
                )
            )
            return AutomationResult(
                message: "Slot sketch profile created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .offsetBodyFace(let target, let distance):
            let result = try session.execute(
                .offsetBodyFace(
                    target: target,
                    distance: distance
                )
            )
            return AutomationResult(
                message: "Body face offset applied.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .deleteBodyFaces(let targets):
            let result = try session.execute(
                .deleteBodyFaces(targets: targets)
            )
            return AutomationResult(
                message: "Body face deletion applied.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .draftBodyFaces(let targets, let neutralTarget, let angle):
            let result = try session.execute(
                .draftBodyFaces(
                    targets: targets,
                    neutralTarget: neutralTarget,
                    angle: angle
                )
            )
            return AutomationResult(
                message: "Body face draft applied.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .chamferBodyEdges(let targets, let distance):
            let result = try session.execute(
                .chamferBodyEdges(
                    targets: targets,
                    distance: distance
                )
            )
            return AutomationResult(
                message: "Body edge chamfer applied.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .filletBodyEdges(let targets, let radius, let segmentCount):
            let result = try session.execute(
                .filletBodyEdges(
                    targets: targets,
                    radius: radius,
                    segmentCount: segmentCount
                )
            )
            return AutomationResult(
                message: "Body edge fillet applied.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .moveBodyEdge(let target, let deltaX, let deltaY):
            let result = try session.execute(
                .moveBodyEdge(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            )
            return AutomationResult(
                message: "Body edge moved.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .moveBodyVertex(let target, let deltaX, let deltaY):
            let result = try session.execute(
                .moveBodyVertex(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            )
            return AutomationResult(
                message: "Body vertex moved.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .moveSketchEntityPoint(let target, let handle, let deltaX, let deltaY):
            let result = try session.execute(
                .moveSketchEntityPoint(
                    target: target,
                    handle: handle,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            )
            return AutomationResult(
                message: "Sketch entity point moved.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .moveSketchSplineControlPoint(let target, let controlPointIndex, let deltaX, let deltaY):
            let result = try session.execute(
                .moveSketchSplineControlPoint(
                    target: target,
                    controlPointIndex: controlPointIndex,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            )
            return AutomationResult(
                message: "Sketch spline control point moved.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .alignSketchVertex(let target, let reference, let options):
            let result = try session.execute(
                .alignSketchVertex(
                    target: target,
                    reference: reference,
                    options: options
                )
            )
            return AutomationResult(
                message: "Sketch vertex aligned.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .slideSketchSplineControlPoints(let target, let controlPointIndexes, let direction, let distance):
            let result = try session.execute(
                .slideSketchSplineControlPoints(
                    target: target,
                    controlPointIndexes: controlPointIndexes,
                    direction: direction,
                    distance: distance
                )
            )
            return AutomationResult(
                message: "Sketch spline control points slid.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .insertSketchSplineControlPoint(let target, let fraction):
            let result = try session.execute(
                .insertSketchSplineControlPoint(
                    target: target,
                    fraction: fraction
                )
            )
            return AutomationResult(
                message: "Sketch spline control point inserted.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSketchCircleParameters(let target, let center, let radius):
            let result = try session.execute(
                .setSketchCircleParameters(
                    target: target,
                    center: center,
                    radius: radius
                )
            )
            return AutomationResult(
                message: "Sketch circle parameters updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSketchArcParameters(let target, let center, let radius, let startAngle, let endAngle):
            let result = try session.execute(
                .setSketchArcParameters(
                    target: target,
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle
                )
            )
            return AutomationResult(
                message: "Sketch arc parameters updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSketchEntityDimension(let target, let kind, let value):
            let result = try session.execute(
                .setSketchEntityDimension(
                    target: target,
                    kind: kind,
                    value: value
                )
            )
            return AutomationResult(
                message: "Sketch entity dimension updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .convertSketchLineToArc(let target, let sagitta):
            let result = try session.execute(
                .convertSketchLineToArc(
                    target: target,
                    sagitta: sagitta
                )
            )
            return AutomationResult(
                message: "Sketch line converted to an arc.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .convertSketchLineToSpline(let target):
            let result = try session.execute(
                .convertSketchLineToSpline(target: target)
            )
            return AutomationResult(
                message: "Sketch line converted to a spline.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .reverseSketchCurve(let target):
            let result = try session.execute(
                .reverseSketchCurve(target: target)
            )
            return AutomationResult(
                message: "Sketch curve direction reversed.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .rebuildSketchCurve(let target, let options):
            let result = try session.execute(
                .rebuildSketchCurve(
                    target: target,
                    options: options
                )
            )
            return AutomationResult(
                message: "Sketch curve rebuilt.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics,
                curveRebuildReport: result.curveRebuildReport
            )
        case .extendSketchCurve(let target, let distance, let shape):
            let result = try session.execute(
                .extendSketchCurve(
                    target: target,
                    distance: distance,
                    shape: shape
                )
            )
            return AutomationResult(
                message: "Sketch curve extended.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .joinSketchCurves(let target, let adjacentTarget, let continuity):
            let result = try session.execute(
                .joinSketchCurves(
                    target: target,
                    adjacentTarget: adjacentTarget,
                    continuity: continuity
                )
            )
            return AutomationResult(
                message: "Sketch curves joined.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .unjoinSketchCurve(let target):
            let result = try session.execute(
                .unjoinSketchCurve(target: target)
            )
            return AutomationResult(
                message: "Sketch curve unjoined.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .splitSketchCurve(let target, let fraction):
            let result = try session.execute(
                .splitSketchCurve(
                    target: target,
                    fraction: fraction
                )
            )
            return AutomationResult(
                message: "Sketch curve segment split.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .trimSketchCurveSegment(let target):
            let result = try session.execute(
                .trimSketchCurveSegment(target: target)
            )
            return AutomationResult(
                message: "Sketch curve segment trimmed.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .cutSketchCurve(let target, let cutter, let options):
            let result = try session.execute(
                .cutSketchCurve(
                    target: target,
                    cutter: cutter,
                    options: options
                )
            )
            return AutomationResult(
                message: "Cut Curve applied.",
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
        case .setExtrudeDistance(let featureID, let distance):
            let result = try session.execute(
                .setExtrudeDistance(
                    featureID: featureID,
                    distance: distance
                )
            )
            return AutomationResult(
                message: "Extrude distance updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setCubeDimensions(let featureID, let sizeX, let sizeY, let sizeZ):
            let result = try session.execute(
                .setCubeDimensions(
                    featureID: featureID,
                    sizeX: sizeX,
                    sizeY: sizeY,
                    sizeZ: sizeZ
                )
            )
            return AutomationResult(
                message: "Cube dimensions updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setCylinderDimensions(let featureID, let radius, let sizeY):
            let result = try session.execute(
                .setCylinderDimensions(
                    featureID: featureID,
                    radius: radius,
                    sizeY: sizeY
                )
            )
            return AutomationResult(
                message: "Cylinder dimensions updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createRevolve(let name, let profile, let axis, let angle):
            let result = try session.execute(
                .createRevolve(
                    name: name,
                    profile: profile,
                    axis: axis,
                    angle: angle
                )
            )
            return AutomationResult(
                message: "Revolve \(name) source created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createSweep(let name, let sections, let path, let guides, let targets, let options):
            let result = try session.execute(
                .createSweep(
                    name: name,
                    sections: sections,
                    path: path,
                    guides: guides,
                    targets: targets,
                    options: options
                )
            )
            return AutomationResult(
                message: "Sweep \(name) source created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createLoft(let name, let sections, let guides, let options):
            let result = try session.execute(
                .createLoft(
                    name: name,
                    sections: sections,
                    guides: guides,
                    options: options
                )
            )
            return AutomationResult(
                message: "Loft \(name) source created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createBoolean(let name, let targets, let tool, let operation, let keepTools):
            let result = try session.execute(
                .createBoolean(
                    name: name,
                    targets: targets,
                    tool: tool,
                    operation: operation,
                    keepTools: keepTools
                )
            )
            return AutomationResult(
                message: "Boolean \(name) source created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createPolySplineSurface(let name, let sourceMesh, let options):
            let result = try session.execute(
                .createPolySplineSurface(
                    name: name,
                    sourceMesh: sourceMesh,
                    options: options
                )
            )
            return AutomationResult(
                message: "PolySpline surface \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .createBSplineSurface(let name, let surface):
            let result = try session.execute(
                .createBSplineSurface(
                    name: name,
                    surface: surface
                )
            )
            return AutomationResult(
                message: "B-spline surface \(name) created.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceFrameDisplay(let query, let isVisible):
            let result = try session.execute(
                .setSurfaceFrameDisplay(query: query, isVisible: isVisible)
            )
            let visibility = isVisible.map { $0 ? "visible" : "hidden" } ?? "toggled"
            return AutomationResult(
                message: "Surface frame display \(visibility).",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .movePolySplineSurfaceVertex(let target, let deltaX, let deltaY, let deltaZ):
            let result = try session.execute(
                .movePolySplineSurfaceVertex(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaZ: deltaZ
                )
            )
            return AutomationResult(
                message: "PolySpline surface vertex moved.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .moveSurfaceControlPoint(let target, let deltaX, let deltaY, let deltaZ):
            let result = try session.execute(
                .moveSurfaceControlPoint(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaZ: deltaZ
                )
            )
            return AutomationResult(
                message: "Surface control point moved.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .moveSurfaceControlPointsInFrame(
            let targets,
            let frame,
            let uDistance,
            let vDistance,
            let normalDistance
        ):
            let result = try session.execute(
                .moveSurfaceControlPointsInFrame(
                    targets: targets,
                    frame: frame,
                    uDistance: uDistance,
                    vDistance: vDistance,
                    normalDistance: normalDistance
                )
            )
            return AutomationResult(
                message: "Surface control points moved in frame.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceControlPointWeight(let target, let weight):
            let result = try session.execute(
                .setSurfaceControlPointWeight(target: target, weight: weight)
            )
            return AutomationResult(
                message: "Surface control point weight updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceKnotValue(let target, let value):
            let result = try session.execute(
                .setSurfaceKnotValue(target: target, value: value)
            )
            return AutomationResult(
                message: "Surface knot value updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .insertSurfaceKnot(let target, let value):
            let result = try session.execute(
                .insertSurfaceKnot(target: target, value: value)
            )
            return AutomationResult(
                message: "Surface knot inserted.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .splitSurfaceSpan(let target, let fraction):
            let result = try session.execute(
                .splitSurfaceSpan(target: target, fraction: fraction)
            )
            return AutomationResult(
                message: "Surface span split.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceKnotMultiplicity(let target, let multiplicity):
            let result = try session.execute(
                .setSurfaceKnotMultiplicity(target: target, multiplicity: multiplicity)
            )
            return AutomationResult(
                message: "Surface knot multiplicity updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceTrimDomain(
            let target,
            let uLowerBound,
            let uUpperBound,
            let vLowerBound,
            let vUpperBound
        ):
            let result = try session.execute(
                .setSurfaceTrimDomain(
                    target: target,
                    uLowerBound: uLowerBound,
                    uUpperBound: uUpperBound,
                    vLowerBound: vLowerBound,
                    vUpperBound: vUpperBound
                )
            )
            return AutomationResult(
                message: "Surface trim domain updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceTrimLoops(let target, let trimLoops):
            let result = try session.execute(
                .setSurfaceTrimLoops(
                    target: target,
                    trimLoops: trimLoops
                )
            )
            return AutomationResult(
                message: "Surface trim loops updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .moveSurfaceTrimEndpoint(let target, let endpoint, let u, let v):
            let result = try session.execute(
                .moveSurfaceTrimEndpoint(
                    target: target,
                    endpoint: endpoint,
                    u: u,
                    v: v
                )
            )
            return AutomationResult(
                message: "Surface trim endpoint moved.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .moveSurfaceTrimControlPoint(let target, let controlPointIndex, let u, let v):
            let result = try session.execute(
                .moveSurfaceTrimControlPoint(
                    target: target,
                    controlPointIndex: controlPointIndex,
                    u: u,
                    v: v
                )
            )
            return AutomationResult(
                message: "Surface trim control point moved.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceTrimControlPointWeight(let target, let controlPointIndex, let weight):
            let result = try session.execute(
                .setSurfaceTrimControlPointWeight(
                    target: target,
                    controlPointIndex: controlPointIndex,
                    weight: weight
                )
            )
            return AutomationResult(
                message: "Surface trim control point weight updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .insertSurfaceTrimKnot(let target, let value):
            let result = try session.execute(
                .insertSurfaceTrimKnot(
                    target: target,
                    value: value
                )
            )
            return AutomationResult(
                message: "Surface trim p-curve knot inserted.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceTrimKnotValue(let target, let knotIndex, let value):
            let result = try session.execute(
                .setSurfaceTrimKnotValue(
                    target: target,
                    knotIndex: knotIndex,
                    value: value
                )
            )
            return AutomationResult(
                message: "Surface trim p-curve knot value updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .setSurfaceTrimKnotMultiplicity(let target, let knotIndex, let multiplicity):
            let result = try session.execute(
                .setSurfaceTrimKnotMultiplicity(
                    target: target,
                    knotIndex: knotIndex,
                    multiplicity: multiplicity
                )
            )
            return AutomationResult(
                message: "Surface trim p-curve knot multiplicity updated.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .matchSurfaceBoundaryContinuity(
            let target,
            let reference,
            let level,
            let matchSide,
            let referenceDirection
        ):
            let result = try session.execute(
                .matchSurfaceBoundaryContinuity(
                    target: target,
                    reference: reference,
                    level: level,
                    matchSide: matchSide,
                    referenceDirection: referenceDirection
                )
            )
            return AutomationResult(
                message: "Surface boundary continuity matched.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .slidePolySplineSurfaceVertices(let targets, let direction, let distance):
            let result = try session.execute(
                .slidePolySplineSurfaceVertices(
                    targets: targets,
                    direction: direction,
                    distance: distance
                )
            )
            return AutomationResult(
                message: "PolySpline surface vertices slid.",
                commandName: result.commandName,
                generation: result.generation,
                didMutate: result.didMutate,
                diagnostics: result.diagnostics
            )
        case .slideSurfaceControlPoints(let targets, let direction, let distance):
            let result = try session.execute(
                .slideSurfaceControlPoints(
                    targets: targets,
                    direction: direction,
                    distance: distance
                )
            )
            return AutomationResult(
                message: "Surface control points slid.",
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

    private func sketchCornerTreatmentAutomationMessage(
        _ treatment: SketchCornerTreatment
    ) -> String {
        switch treatment {
        case .fillet:
            "Sketch corner fillet applied."
        case .chamfer:
            "Sketch corner chamfer applied."
        }
    }
}
