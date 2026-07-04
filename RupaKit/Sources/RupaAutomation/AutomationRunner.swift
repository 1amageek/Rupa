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
            let scale = WorkspaceScaleSnapshot(ruler: session.document.ruler)
            return workspaceAutomationResult(
                message: "Document uses \(session.document.displayUnit.symbol) display units. \(scale.summary)",
                in: session
            )
        case .setDisplayUnit(let unit):
            let result = try session.execute(.setDisplayUnit(unit))
            let scale = WorkspaceScaleSnapshot(ruler: session.document.ruler)
            return workspaceAutomationResult(
                message: "Display unit changed to \(unit.symbol). \(scale.summary)",
                commandResult: result,
                in: session
            )
        case .setRulerConfiguration(let configuration):
            let normalized = configuration.normalizedForWorkspaceScale()
            let result = try session.execute(.setRulerConfiguration(normalized))
            let scale = WorkspaceScaleSnapshot(ruler: session.document.ruler)
            return workspaceAutomationResult(
                message: "Ruler configuration changed. \(scale.summary)",
                commandResult: result,
                in: session
            )
        case .setWorkspaceScalePreset(let preset):
            let configuration = preset.rulerConfiguration.normalizedForWorkspaceScale()
            let result = try session.execute(.setRulerConfiguration(configuration))
            let scale = WorkspaceScaleSnapshot(ruler: session.document.ruler)
            return workspaceAutomationResult(
                message: "Workspace scale preset changed to \(preset.title). \(scale.summary)",
                commandResult: result,
                in: session
            )
        case .fitWorkspaceScaleToModel:
            return try fitWorkspaceScaleToModel(in: session)
        case .setViewportGridSettings(let settings):
            let result = try session.execute(.setViewportGridSettings(settings))
            return workspaceAutomationResult(
                message: "Viewport grid settings changed. \(settings.summary)",
                commandResult: result,
                in: session
            )
        case .describeSavedViews:
            let savedViews = sortedSavedViews(in: session)
            return workspaceAutomationResult(
                message: "\(savedViews.count) saved view(s).",
                in: session
            )
        case .createSavedView(let savedView):
            let result = try session.execute(.createSavedView(savedView))
            let createdName = session.document.productMetadata.savedViews[savedView.id]?.name ?? savedView.name
            return commandAutomationResult(
                message: "Saved view \(createdName) created.",
                commandResult: result,
                savedViewID: savedView.id,
                in: session
            )
        case .updateSavedView(let savedView):
            let result = try session.execute(.updateSavedView(savedView))
            let updatedName = session.document.productMetadata.savedViews[savedView.id]?.name ?? savedView.name
            return commandAutomationResult(
                message: "Saved view \(updatedName) updated.",
                commandResult: result,
                savedViewID: savedView.id,
                in: session
            )
        case .removeSavedView(let id):
            let removedName = session.document.productMetadata.savedViews[id]?.name ?? id.description
            let result = try session.execute(.removeSavedView(id: id))
            return commandAutomationResult(
                message: "Saved view \(removedName) removed.",
                commandResult: result,
                savedViewID: id,
                in: session
            )
        case .rebaseWorkspaceOrigin(let translation):
            let result = try session.execute(.rebaseWorkspaceOrigin(translation: translation))
            return workspaceAutomationResult(
                message: "Workspace origin rebased by (\(translation.x), \(translation.y), \(translation.z)) m.",
                commandResult: result,
                in: session
            )
        case .renameDocument(let name):
            let result = try session.execute(.renameDocument(name: name))
            return commandAutomationResult(
                message: "Document renamed to \(name).",
                commandResult: result,
                in: session
            )
        case .upsertParameter(let name, let expression, let kind):
            let result = try session.execute(
                .upsertParameter(
                    name: name,
                    expression: expression,
                    kind: kind
                )
            )
            return commandAutomationResult(
                message: "Parameter \(name) updated.",
                commandResult: result,
                in: session
            )
        case .renameParameter(let currentName, let newName):
            let result = try session.execute(
                .renameParameter(
                    currentName: currentName,
                    newName: newName
                )
            )
            return commandAutomationResult(
                message: "Parameter \(currentName) renamed to \(newName).",
                commandResult: result,
                in: session
            )
        case .deleteParameter(let name):
            let result = try session.execute(.deleteParameter(name: name))
            return commandAutomationResult(
                message: "Parameter \(name) deleted.",
                commandResult: result,
                in: session
            )
        case .createComponentDefinition(let name, let rootSceneNodeIDs):
            let result = try session.execute(
                .createComponentDefinition(
                    name: name,
                    rootSceneNodeIDs: rootSceneNodeIDs
                )
            )
            return commandAutomationResult(
                message: "Component definition \(name) created.",
                commandResult: result,
                in: session
            )
        case .createComponentInstance(let name, let definitionID, let localTransform):
            let result = try session.execute(
                .createComponentInstance(
                    name: name,
                    definitionID: definitionID,
                    localTransform: localTransform
                )
            )
            return commandAutomationResult(
                message: "Component instance \(name) created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Pattern array \(name) created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Pattern array updated.",
                commandResult: result,
                in: session
            )
        case .explodePatternArray(let id):
            let result = try session.execute(.explodePatternArray(id: id))
            return commandAutomationResult(
                message: "Pattern array exploded.",
                commandResult: result,
                in: session
            )
        case .setSceneNodeVisibility(let id, let isVisible):
            let result = try session.execute(
                .setSceneNodeVisibility(id: id, isVisible: isVisible)
            )
            return commandAutomationResult(
                message: "Scene node visibility updated.",
                commandResult: result,
                in: session
            )
        case .setSceneNodeLock(let id, let isLocked):
            let result = try session.execute(
                .setSceneNodeLock(id: id, isLocked: isLocked)
            )
            return commandAutomationResult(
                message: "Scene node lock updated.",
                commandResult: result,
                in: session
            )
        case .setSceneNodeTransform(let id, let localTransform):
            let result = try session.execute(
                .setSceneNodeTransform(
                    id: id,
                    localTransform: localTransform
                )
            )
            return commandAutomationResult(
                message: "Scene node transform updated.",
                commandResult: result,
                in: session
            )
        case .setComponentInstanceVisibility(let id, let isVisible):
            let result = try session.execute(
                .setComponentInstanceVisibility(id: id, isVisible: isVisible)
            )
            return commandAutomationResult(
                message: "Component instance visibility updated.",
                commandResult: result,
                in: session
            )
        case .setComponentInstanceLock(let id, let isLocked):
            let result = try session.execute(
                .setComponentInstanceLock(id: id, isLocked: isLocked)
            )
            return commandAutomationResult(
                message: "Component instance lock updated.",
                commandResult: result,
                in: session
            )
        case .setComponentInstanceTransform(let id, let localTransform):
            let result = try session.execute(
                .setComponentInstanceTransform(
                    id: id,
                    localTransform: localTransform
                )
            )
            return commandAutomationResult(
                message: "Component instance transform updated.",
                commandResult: result,
                in: session
            )
        case .createSectionPlane(let name):
            let result = try session.execute(.createSectionPlane(name: name))
            return commandAutomationResult(
                message: "Section plane \(name) created.",
                commandResult: result,
                in: session
            )
        case .analyzeSection(let query):
            let result = try SectionAnalysisService().analyze(
                document: session.document,
                query: query,
                objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation,
                currentGeneration: session.generation
            )
            return sectionAnalysisAutomationResult(
                result,
                clipping: query.clipping,
                in: session
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
            return commandAutomationResult(
                message: "Construction plane \(name) created.",
                commandResult: result,
                in: session
            )
        case .createConstructionPlaneFromTarget(let name, let target, let activates):
            let result = try session.execute(
                .createConstructionPlaneFromTarget(
                    name: name,
                    target: target,
                    activates: activates
                )
            )
            return commandAutomationResult(
                message: "Construction plane \(name) created from target \(target.component).",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Construction plane \(name) created from \(targets.count) targets.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "View-aligned construction plane \(name) created.",
                commandResult: result,
                in: session
            )
        case .setActiveConstructionPlane(let id):
            let result = try session.execute(.setActiveConstructionPlane(id: id))
            let activeName = session.activeConstructionPlane?.name ?? "none"
            return commandAutomationResult(
                message: "Active construction plane set to \(activeName).",
                commandResult: result,
                in: session
            )
        case .renameConstructionPlane(let id, let name):
            let result = try session.execute(.renameConstructionPlane(id: id, name: name))
            let renamedName = session.document.productMetadata.constructionPlanes[id]?.name ?? name
            return commandAutomationResult(
                message: "Construction plane renamed to \(renamedName).",
                commandResult: result,
                in: session
            )
        case .setConstructionPlane(let id, let plane):
            let result = try session.execute(.setConstructionPlane(id: id, plane: plane))
            let editedName = session.document.productMetadata.constructionPlanes[id]?.name ?? id.description
            return commandAutomationResult(
                message: "Construction plane \(editedName) updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Curve curvature display \(visibility)\(scale).",
                commandResult: result,
                in: session
            )
        case .setPointDisplay(let target, let isVisible):
            let result = try session.execute(
                .setPointDisplay(target: target, isVisible: isVisible)
            )
            let visibility = isVisible.map { $0 ? "visible" : "hidden" } ?? "toggled"
            return commandAutomationResult(
                message: "Point display \(visibility).",
                commandResult: result,
                in: session
            )
        case .setSurfaceControlPointDisplay(let target, let isVisible):
            let result = try session.execute(
                .setSurfaceControlPointDisplay(target: target, isVisible: isVisible)
            )
            let visibility = isVisible.map { $0 ? "visible" : "hidden" } ?? "toggled"
            return commandAutomationResult(
                message: "Surface control point display \(visibility).",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Sketch \(name) created with \(sketch.entities.count) \(entityLabel).",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Line sketch \(name) created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Circle sketch \(name) created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Arc sketch \(name) created.",
                commandResult: result,
                in: session
            )
        case .createSplineSketch(let name, let plane, let spline):
            let result = try session.execute(
                .createSplineSketch(
                    name: name,
                    plane: plane,
                    spline: spline
                )
            )
            return commandAutomationResult(
                message: "Spline sketch \(name) created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Rectangle sketch \(name) created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Polygon sketch \(name) created.",
                commandResult: result,
                in: session
            )
        case .createFaceKnife(let name, let target, let loop):
            let result = try session.execute(
                .createFaceKnife(
                    name: name,
                    target: target,
                    loop: loop
                )
            )
            return commandAutomationResult(
                message: "Face Knife \(name) applied.",
                commandResult: result,
                in: session
            )
        case .projectSketchCurvesToConstructionPlane(let targets, let plane, let name):
            let result = try session.execute(
                .projectSketchCurvesToConstructionPlane(
                    targets: targets,
                    plane: plane,
                    name: name
                )
            )
            return commandAutomationResult(
                message: "Sketch curves projected.",
                commandResult: result,
                in: session
            )
        case .projectCurvesToGeneratedFace(let targets, let face, let name):
            let result = try session.execute(
                .projectCurvesToGeneratedFace(
                    targets: targets,
                    face: face,
                    name: name
                )
            )
            return commandAutomationResult(
                message: "Curves projected to generated face.",
                commandResult: result,
                in: session
            )
        case .projectBodyOutlinesToConstructionPlane(let targets, let plane, let name):
            let result = try session.execute(
                .projectBodyOutlinesToConstructionPlane(
                    targets: targets,
                    plane: plane,
                    name: name
                )
            )
            return commandAutomationResult(
                message: "Body outlines projected.",
                commandResult: result,
                in: session
            )
        case .setObjectDimension(let target, let kind, let value):
            let result = try session.execute(
                .setObjectDimension(
                    target: target,
                    kind: kind,
                    value: value
                )
            )
            return commandAutomationResult(
                message: "Object dimension updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Selection dimension added.",
                commandResult: result,
                in: session
            )
        case .setSelectionDimensionTarget(let id, let target):
            let result = try session.execute(
                .setSelectionDimensionTarget(
                    id: id,
                    target: target
                )
            )
            return commandAutomationResult(
                message: "Selection dimension target updated.",
                commandResult: result,
                in: session
            )
        case .applySelectionDimensionTarget(let id):
            let result = try session.execute(.applySelectionDimensionTarget(id: id))
            return commandAutomationResult(
                message: "Selection dimension target applied.",
                commandResult: result,
                in: session
            )
        case .removeSelectionDimension(let id):
            let result = try session.execute(.removeSelectionDimension(id: id))
            return commandAutomationResult(
                message: "Selection dimension removed.",
                commandResult: result,
                in: session
            )
        case .addSketchConstraint(let featureID, let constraint):
            let result = try session.execute(
                .addSketchConstraint(
                    featureID: featureID,
                    constraint: constraint
                )
            )
            return commandAutomationResult(
                message: "Sketch constraint added to \(featureID.description).",
                commandResult: result,
                in: session
            )
        case .removeSketchConstraint(let featureID, let constraint):
            let result = try session.execute(
                .removeSketchConstraint(
                    featureID: featureID,
                    constraint: constraint
                )
            )
            return commandAutomationResult(
                message: "Sketch constraint removed from \(featureID.description).",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Bridge curve created in sketch \(featureID.description).",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Bridge curve \(sourceID.description) updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: message,
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: combinesRegions ? "Combined sketch regions offset created." : "Sketch regions offset created.",
                commandResult: result,
                in: session
            )
        case .offsetSketchVertex(let target, let handle, let distance):
            let result = try session.execute(
                .offsetSketchVertex(
                    target: target,
                    handle: handle,
                    distance: distance
                )
            )
            return commandAutomationResult(
                message: "Sketch vertex offset created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: sketchCornerTreatmentAutomationMessage(treatment),
                commandResult: result,
                in: session
            )
        case .createSlotSketch(let target, let width):
            let result = try session.execute(
                .createSlotSketch(
                    target: target,
                    width: width
                )
            )
            return commandAutomationResult(
                message: "Slot sketch profile created.",
                commandResult: result,
                in: session
            )
        case .offsetBodyFace(let target, let distance):
            let result = try session.execute(
                .offsetBodyFace(
                    target: target,
                    distance: distance
                )
            )
            return commandAutomationResult(
                message: "Body face offset applied.",
                commandResult: result,
                in: session
            )
        case .deleteBodyFaces(let targets):
            let result = try session.execute(
                .deleteBodyFaces(targets: targets)
            )
            return commandAutomationResult(
                message: "Body face deletion applied.",
                commandResult: result,
                in: session
            )
        case .draftBodyFaces(let targets, let neutralTarget, let angle):
            let result = try session.execute(
                .draftBodyFaces(
                    targets: targets,
                    neutralTarget: neutralTarget,
                    angle: angle
                )
            )
            return commandAutomationResult(
                message: "Body face draft applied.",
                commandResult: result,
                in: session
            )
        case .chamferBodyEdges(let targets, let distance):
            let result = try session.execute(
                .chamferBodyEdges(
                    targets: targets,
                    distance: distance
                )
            )
            return commandAutomationResult(
                message: "Body edge chamfer applied.",
                commandResult: result,
                in: session
            )
        case .filletBodyEdges(let targets, let radius, let segmentCount):
            let result = try session.execute(
                .filletBodyEdges(
                    targets: targets,
                    radius: radius,
                    segmentCount: segmentCount
                )
            )
            return commandAutomationResult(
                message: "Body edge fillet applied.",
                commandResult: result,
                in: session
            )
        case .moveBodyEdge(let target, let deltaX, let deltaY):
            let result = try session.execute(
                .moveBodyEdge(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            )
            return commandAutomationResult(
                message: "Body edge moved.",
                commandResult: result,
                in: session
            )
        case .moveBodyVertex(let target, let deltaX, let deltaY):
            let result = try session.execute(
                .moveBodyVertex(
                    target: target,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            )
            return commandAutomationResult(
                message: "Body vertex moved.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Sketch entity point moved.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Sketch spline control point moved.",
                commandResult: result,
                in: session
            )
        case .alignSketchVertex(let target, let reference, let options):
            let result = try session.execute(
                .alignSketchVertex(
                    target: target,
                    reference: reference,
                    options: options
                )
            )
            return commandAutomationResult(
                message: "Sketch vertex aligned.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Sketch spline control points slid.",
                commandResult: result,
                in: session
            )
        case .insertSketchSplineControlPoint(let target, let fraction):
            let result = try session.execute(
                .insertSketchSplineControlPoint(
                    target: target,
                    fraction: fraction
                )
            )
            return commandAutomationResult(
                message: "Sketch spline control point inserted.",
                commandResult: result,
                in: session
            )
        case .setSketchCircleParameters(let target, let center, let radius):
            let result = try session.execute(
                .setSketchCircleParameters(
                    target: target,
                    center: center,
                    radius: radius
                )
            )
            return commandAutomationResult(
                message: "Sketch circle parameters updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Sketch arc parameters updated.",
                commandResult: result,
                in: session
            )
        case .setSketchEntityDimension(let target, let kind, let value):
            let result = try session.execute(
                .setSketchEntityDimension(
                    target: target,
                    kind: kind,
                    value: value
                )
            )
            return commandAutomationResult(
                message: "Sketch entity dimension updated.",
                commandResult: result,
                in: session
            )
        case .convertSketchLineToArc(let target, let sagitta):
            let result = try session.execute(
                .convertSketchLineToArc(
                    target: target,
                    sagitta: sagitta
                )
            )
            return commandAutomationResult(
                message: "Sketch line converted to an arc.",
                commandResult: result,
                in: session
            )
        case .convertSketchLineToSpline(let target):
            let result = try session.execute(
                .convertSketchLineToSpline(target: target)
            )
            return commandAutomationResult(
                message: "Sketch line converted to a spline.",
                commandResult: result,
                in: session
            )
        case .reverseSketchCurve(let target):
            let result = try session.execute(
                .reverseSketchCurve(target: target)
            )
            return commandAutomationResult(
                message: "Sketch curve direction reversed.",
                commandResult: result,
                in: session
            )
        case .rebuildSketchCurve(let target, let options):
            let result = try session.execute(
                .rebuildSketchCurve(
                    target: target,
                    options: options
                )
            )
            return commandAutomationResult(
                message: "Sketch curve rebuilt.",
                commandResult: result,
                in: session
            )
        case .extendSketchCurve(let target, let distance, let shape):
            let result = try session.execute(
                .extendSketchCurve(
                    target: target,
                    distance: distance,
                    shape: shape
                )
            )
            return commandAutomationResult(
                message: "Sketch curve extended.",
                commandResult: result,
                in: session
            )
        case .joinSketchCurves(let target, let adjacentTarget, let continuity):
            let result = try session.execute(
                .joinSketchCurves(
                    target: target,
                    adjacentTarget: adjacentTarget,
                    continuity: continuity
                )
            )
            return commandAutomationResult(
                message: "Sketch curves joined.",
                commandResult: result,
                in: session
            )
        case .unjoinSketchCurve(let target):
            let result = try session.execute(
                .unjoinSketchCurve(target: target)
            )
            return commandAutomationResult(
                message: "Sketch curve unjoined.",
                commandResult: result,
                in: session
            )
        case .splitSketchCurve(let target, let fraction):
            let result = try session.execute(
                .splitSketchCurve(
                    target: target,
                    fraction: fraction
                )
            )
            return commandAutomationResult(
                message: "Sketch curve segment split.",
                commandResult: result,
                in: session
            )
        case .trimSketchCurveSegment(let target):
            let result = try session.execute(
                .trimSketchCurveSegment(target: target)
            )
            return commandAutomationResult(
                message: "Sketch curve segment trimmed.",
                commandResult: result,
                in: session
            )
        case .cutSketchCurve(let target, let cutter, let options):
            let result = try session.execute(
                .cutSketchCurve(
                    target: target,
                    cutter: cutter,
                    options: options
                )
            )
            return commandAutomationResult(
                message: "Cut Curve applied.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Profile extrude \(name) created.",
                commandResult: result,
                in: session
            )
        case .setExtrudeDistance(let featureID, let distance):
            let result = try session.execute(
                .setExtrudeDistance(
                    featureID: featureID,
                    distance: distance
                )
            )
            return commandAutomationResult(
                message: "Extrude distance updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Cube dimensions updated.",
                commandResult: result,
                in: session
            )
        case .setCylinderDimensions(let featureID, let radius, let sizeY):
            let result = try session.execute(
                .setCylinderDimensions(
                    featureID: featureID,
                    radius: radius,
                    sizeY: sizeY
                )
            )
            return commandAutomationResult(
                message: "Cylinder dimensions updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Revolve \(name) source created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Sweep \(name) source created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Loft \(name) source created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Boolean \(name) source created.",
                commandResult: result,
                in: session
            )
        case .createPolySplineSurface(let name, let sourceMesh, let options):
            let result = try session.execute(
                .createPolySplineSurface(
                    name: name,
                    sourceMesh: sourceMesh,
                    options: options
                )
            )
            return commandAutomationResult(
                message: "PolySpline surface \(name) created.",
                commandResult: result,
                in: session
            )
        case .createBSplineSurface(let name, let surface):
            let result = try session.execute(
                .createBSplineSurface(
                    name: name,
                    surface: surface
                )
            )
            return commandAutomationResult(
                message: "B-spline surface \(name) created.",
                commandResult: result,
                in: session
            )
        case .setSurfaceFrameDisplay(let query, let isVisible):
            let result = try session.execute(
                .setSurfaceFrameDisplay(query: query, isVisible: isVisible)
            )
            let visibility = isVisible.map { $0 ? "visible" : "hidden" } ?? "toggled"
            return commandAutomationResult(
                message: "Surface frame display \(visibility).",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "PolySpline surface vertex moved.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Surface control point moved.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Surface control points moved in frame.",
                commandResult: result,
                in: session
            )
        case .setSurfaceControlPointWeight(let target, let weight):
            let result = try session.execute(
                .setSurfaceControlPointWeight(target: target, weight: weight)
            )
            return commandAutomationResult(
                message: "Surface control point weight updated.",
                commandResult: result,
                in: session
            )
        case .setSurfaceKnotValue(let target, let value):
            let result = try session.execute(
                .setSurfaceKnotValue(target: target, value: value)
            )
            return commandAutomationResult(
                message: "Surface knot value updated.",
                commandResult: result,
                in: session
            )
        case .insertSurfaceKnot(let target, let value):
            let result = try session.execute(
                .insertSurfaceKnot(target: target, value: value)
            )
            return commandAutomationResult(
                message: "Surface knot inserted.",
                commandResult: result,
                in: session
            )
        case .splitSurfaceSpan(let target, let fraction):
            let result = try session.execute(
                .splitSurfaceSpan(target: target, fraction: fraction)
            )
            return commandAutomationResult(
                message: "Surface span split.",
                commandResult: result,
                in: session
            )
        case .setSurfaceKnotMultiplicity(let target, let multiplicity):
            let result = try session.execute(
                .setSurfaceKnotMultiplicity(target: target, multiplicity: multiplicity)
            )
            return commandAutomationResult(
                message: "Surface knot multiplicity updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Surface trim domain updated.",
                commandResult: result,
                in: session
            )
        case .setSurfaceTrimLoops(let target, let trimLoops):
            let result = try session.execute(
                .setSurfaceTrimLoops(
                    target: target,
                    trimLoops: trimLoops
                )
            )
            return commandAutomationResult(
                message: "Surface trim loops updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Surface trim endpoint moved.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Surface trim control point moved.",
                commandResult: result,
                in: session
            )
        case .setSurfaceTrimControlPointWeight(let target, let controlPointIndex, let weight):
            let result = try session.execute(
                .setSurfaceTrimControlPointWeight(
                    target: target,
                    controlPointIndex: controlPointIndex,
                    weight: weight
                )
            )
            return commandAutomationResult(
                message: "Surface trim control point weight updated.",
                commandResult: result,
                in: session
            )
        case .insertSurfaceTrimKnot(let target, let value):
            let result = try session.execute(
                .insertSurfaceTrimKnot(
                    target: target,
                    value: value
                )
            )
            return commandAutomationResult(
                message: "Surface trim p-curve knot inserted.",
                commandResult: result,
                in: session
            )
        case .setSurfaceTrimKnotValue(let target, let knotIndex, let value):
            let result = try session.execute(
                .setSurfaceTrimKnotValue(
                    target: target,
                    knotIndex: knotIndex,
                    value: value
                )
            )
            return commandAutomationResult(
                message: "Surface trim p-curve knot value updated.",
                commandResult: result,
                in: session
            )
        case .setSurfaceTrimKnotMultiplicity(let target, let knotIndex, let multiplicity):
            let result = try session.execute(
                .setSurfaceTrimKnotMultiplicity(
                    target: target,
                    knotIndex: knotIndex,
                    multiplicity: multiplicity
                )
            )
            return commandAutomationResult(
                message: "Surface trim p-curve knot multiplicity updated.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Surface boundary continuity matched.",
                commandResult: result,
                in: session
            )
        case .slidePolySplineSurfaceVertices(let targets, let direction, let distance):
            let result = try session.execute(
                .slidePolySplineSurfaceVertices(
                    targets: targets,
                    direction: direction,
                    distance: distance
                )
            )
            return commandAutomationResult(
                message: "PolySpline surface vertices slid.",
                commandResult: result,
                in: session
            )
        case .slideSurfaceControlPoints(let targets, let direction, let distance):
            let result = try session.execute(
                .slideSurfaceControlPoints(
                    targets: targets,
                    direction: direction,
                    distance: distance
                )
            )
            return commandAutomationResult(
                message: "Surface control points slid.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Extruded rectangle \(name) created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Extruded rectangle \(name) created.",
                commandResult: result,
                in: session
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
            return commandAutomationResult(
                message: "Extruded circle \(name) created.",
                commandResult: result,
                in: session
            )
        case .validateDocument:
            let result = try session.execute(.validateDocument)
            return commandAutomationResult(
                message: "Validation finished.",
                commandResult: result,
                in: session
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

    private func commandAutomationResult(
        message: String,
        commandResult: CommandExecutionResult,
        savedViewID: SavedViewID? = nil,
        in session: EditorSession
    ) -> AutomationResult {
        workspaceAutomationResult(
            message: message,
            commandResult: commandResult,
            savedViewID: savedViewID,
            in: session
        )
    }

    private func workspaceAutomationResult(
        message: String,
        commandResult: CommandExecutionResult? = nil,
        savedViewID: SavedViewID? = nil,
        in session: EditorSession
    ) -> AutomationResult {
        let context = workspaceAutomationContext(in: session)
        return AutomationResult(
            message: message,
            commandName: commandResult?.commandName,
            generation: commandResult?.generation ?? session.generation,
            didMutate: commandResult?.didMutate ?? false,
            diagnostics: mergedDiagnostics(
                commandResult?.diagnostics ?? session.diagnostics,
                context.diagnostics
            ),
            primaryFeatureID: commandResult?.primaryFeatureID,
            createdFeatureIDs: commandResult?.createdFeatureIDs ?? [],
            curveRebuildReport: commandResult?.curveRebuildReport,
            addedSelectionDimensionID: commandResult?.addedSelectionDimensionID,
            workspaceScale: context.scale,
            workspaceInteractionScale: context.interactionScale,
            workspaceBounds: context.bounds,
            workspacePrecision: context.precision,
            workspaceScaleRecommendation: context.scaleRecommendation,
            workspaceScalePresetOptions: context.scalePresetOptions,
            viewportGridSettings: context.viewportGridSettings,
            viewportGridScale: context.viewportGridScale,
            savedViews: context.savedViews,
            savedViewID: savedViewID
        )
    }

    private func fitWorkspaceScaleToModel(
        in session: EditorSession
    ) throws -> AutomationResult {
        let plan = try WorkspaceScaleFitService().plan(
            document: session.document,
            objectRegistry: session.objectRegistry,
            currentEvaluation: session.currentEvaluation,
            currentGeneration: session.generation
        )

        switch plan.action {
        case .alreadyFits:
            return workspaceAutomationResult(
                message: "Workspace scale already fits the current model.",
                measurement: plan.measurement,
                in: session
            )
        case .unsupportedRange:
            return workspaceAutomationResult(
                message: "Workspace scale cannot fit the current model within the supported preset range.",
                measurement: plan.measurement,
                in: session
            )
        case .applyPreset(let preset):
            let configuration = preset.rulerConfiguration.normalizedForWorkspaceScale()
            let result = try session.execute(.setRulerConfiguration(configuration))
            let scale = WorkspaceScaleSnapshot(ruler: session.document.ruler)
            return workspaceAutomationResult(
                message: "Workspace scale fitted to \(preset.title). \(scale.summary)",
                commandResult: result,
                in: session
            )
        }
    }

    private func workspaceAutomationResult(
        message: String,
        measurement: MeasurementResult,
        in session: EditorSession
    ) -> AutomationResult {
        AutomationResult(
            message: message,
            generation: session.generation,
            didMutate: false,
            diagnostics: measurement.diagnostics,
            workspaceScale: WorkspaceScaleSnapshot(ruler: session.document.ruler),
            workspaceInteractionScale: WorkspaceInteractionScaleSnapshot(ruler: session.document.ruler),
            workspaceBounds: measurement.bounds,
            workspacePrecision: measurement.workspacePrecision,
            workspaceScaleRecommendation: measurement.workspaceScaleRecommendation,
            workspaceScalePresetOptions: WorkspaceScalePreset.profiles,
            viewportGridSettings: session.document.productMetadata.viewportGridSettings,
            viewportGridScale: ViewportGridScaleSnapshot(
                ruler: session.document.ruler,
                settings: session.document.productMetadata.viewportGridSettings
            ),
            savedViews: sortedSavedViews(in: session)
        )
    }

    private func sectionAnalysisAutomationResult(
        _ sectionAnalysis: SectionAnalysisResult,
        clipping: SectionAnalysisClippingRequest?,
        in session: EditorSession
    ) -> AutomationResult {
        let context = workspaceAutomationContext(in: session)
        let clippingPlan = clipping.map { clipping in
            SectionAnalysisClippingPlan(
                result: sectionAnalysis,
                retaining: clipping.retainedSide
            )
        }
        return AutomationResult(
            message: sectionAnalysisMessage(
                sectionAnalysis,
                clippingPlan: clippingPlan
            ),
            commandName: "analyzeSection",
            generation: session.generation,
            didMutate: false,
            diagnostics: mergedDiagnostics(sectionAnalysis.diagnostics, context.diagnostics),
            workspaceScale: context.scale,
            workspaceInteractionScale: context.interactionScale,
            workspaceBounds: context.bounds,
            workspacePrecision: context.precision,
            workspaceScaleRecommendation: context.scaleRecommendation,
            workspaceScalePresetOptions: context.scalePresetOptions,
            viewportGridSettings: context.viewportGridSettings,
            viewportGridScale: context.viewportGridScale,
            savedViews: context.savedViews,
            sectionAnalysis: sectionAnalysis,
            sectionClippingPlan: clippingPlan
        )
    }

    private func sectionAnalysisMessage(
        _ sectionAnalysis: SectionAnalysisResult,
        clippingPlan: SectionAnalysisClippingPlan?
    ) -> String {
        let analysisSummary = "Section analysis completed with \(sectionAnalysis.intersectingBodyCount) intersecting body mesh(es)."
        guard let clippingPlan else {
            return analysisSummary
        }
        return [
            analysisSummary,
            "Clipping plan retains \(clippingPlan.retainedSide.rawValue) side with \(clippingPlan.visibleBodyCount) visible, \(clippingPlan.hiddenBodyCount) hidden, and \(clippingPlan.clippedBodyCount) clipped body mesh(es).",
        ].joined(separator: " ")
    }

    private func workspaceAutomationContext(
        in session: EditorSession
    ) -> WorkspaceAutomationContext {
        let measurementContext = workspaceMeasurement(in: session)
        let bounds = measurementContext.measurement?.bounds ?? session.currentEvaluation.flatMap {
            WorkspaceBoundsService().bounds(for: $0.evaluatedDocument)
        }
        let precision = measurementContext.measurement?.workspacePrecision
            ?? WorkspacePrecisionDiagnosticService().report(
                for: bounds,
                ruler: session.document.ruler
            )
        let recommendation = measurementContext.measurement?.workspaceScaleRecommendation
            ?? WorkspaceScaleRecommendationService().recommendation(
                for: bounds,
                currentRuler: session.document.ruler
            )
        return WorkspaceAutomationContext(
            scale: WorkspaceScaleSnapshot(ruler: session.document.ruler),
            interactionScale: WorkspaceInteractionScaleSnapshot(ruler: session.document.ruler),
            bounds: bounds,
            precision: precision,
            scaleRecommendation: recommendation,
            scalePresetOptions: WorkspaceScalePreset.profiles,
            viewportGridSettings: session.document.productMetadata.viewportGridSettings,
            viewportGridScale: ViewportGridScaleSnapshot(
                ruler: session.document.ruler,
                settings: session.document.productMetadata.viewportGridSettings
            ),
            savedViews: sortedSavedViews(in: session),
            diagnostics: workspaceContextDiagnostics(
                precision: precision,
                recommendation: recommendation,
                displayUnit: session.document.displayUnit
            ) + measurementContext.diagnostics
        )
    }

    private func sortedSavedViews(in session: EditorSession) -> [SavedView] {
        session.document.productMetadata.savedViews.values.sorted {
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id.description < $1.id.description
        }
    }

    private func workspaceMeasurement(
        in session: EditorSession
    ) -> WorkspaceMeasurementContext {
        do {
            let measurement = try MeasurementService().measure(
                document: session.document,
                objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation,
                currentGeneration: session.generation
            )
            return WorkspaceMeasurementContext(measurement: measurement)
        } catch {
            return WorkspaceMeasurementContext(
                measurement: nil,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .warning,
                        message: "Workspace context measurement failed: \(String(describing: error))"
                    ),
                ]
            )
        }
    }

    private func workspaceContextDiagnostics(
        precision: WorkspacePrecisionReport?,
        recommendation: WorkspaceScaleRecommendation?,
        displayUnit: LengthDisplayUnit
    ) -> [EditorDiagnostic] {
        WorkspacePrecisionDiagnosticService().diagnostics(
            for: precision,
            displayUnit: displayUnit
        ) + WorkspaceScaleRecommendationService().diagnostics(
            for: recommendation
        )
    }

    private func mergedDiagnostics(
        _ primary: [EditorDiagnostic],
        _ workspaceDiagnostics: [EditorDiagnostic]
    ) -> [EditorDiagnostic] {
        var result = primary
        for diagnostic in workspaceDiagnostics where !containsEquivalentDiagnostic(
            diagnostic,
            in: result
        ) {
            result.append(diagnostic)
        }
        return result
    }

    private func containsEquivalentDiagnostic(
        _ diagnostic: EditorDiagnostic,
        in diagnostics: [EditorDiagnostic]
    ) -> Bool {
        diagnostics.contains {
            $0.severity == diagnostic.severity
                && $0.code == diagnostic.code
                && $0.message == diagnostic.message
        }
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

private struct WorkspaceMeasurementContext {
    var measurement: MeasurementResult?
    var diagnostics: [EditorDiagnostic]

    init(
        measurement: MeasurementResult?,
        diagnostics: [EditorDiagnostic] = []
    ) {
        self.measurement = measurement
        self.diagnostics = diagnostics
    }
}

private struct WorkspaceAutomationContext {
    var scale: WorkspaceScaleSnapshot
    var interactionScale: WorkspaceInteractionScaleSnapshot
    var bounds: MeasurementResult.Bounds?
    var precision: WorkspacePrecisionReport?
    var scaleRecommendation: WorkspaceScaleRecommendation?
    var scalePresetOptions: [WorkspaceScalePresetProfile]
    var viewportGridSettings: ViewportGridSettings
    var viewportGridScale: ViewportGridScaleSnapshot
    var savedViews: [SavedView]
    var diagnostics: [EditorDiagnostic]
}
