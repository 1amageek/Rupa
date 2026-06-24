import Foundation
import Observation
import SwiftCAD

@Observable
public final class EditorSession {
    public private(set) var store: CADDocumentStore
    public private(set) var commandStack: CommandStack
    public private(set) var selection: SelectionModel
    public private(set) var polygonToolState: PolygonToolState
    public private(set) var sketchInputState: SketchInputState
    public var selectedTool: ModelingTool

    public var document: DesignDocument {
        store.document
    }

    public var generation: DocumentGeneration {
        store.generation
    }

    public var isDirty: Bool {
        store.isDirty
    }

    public var diagnostics: [EditorDiagnostic] {
        store.diagnostics
    }

    public var evaluationStatus: EvaluationStatus {
        store.evaluationStatus
    }

    public var evaluatedGeneration: DocumentGeneration? {
        store.evaluatedGeneration
    }

    public var renderInvalidation: RenderInvalidation {
        store.renderInvalidation
    }

    public var evaluatedBodyCount: Int {
        store.evaluatedBodyCount
    }

    public var currentEvaluationCache: EvaluatedDocumentCache? {
        store.currentEvaluationCache
    }

    public var currentEvaluation: DocumentEvaluationContext? {
        store.currentEvaluation
    }

    public var evaluationSnapshot: EvaluationSnapshot {
        store.evaluationSnapshot
    }

    public var objectRegistry: ObjectTypeRegistry {
        store.objectRegistry
    }

    public var selectedSceneNodeID: SceneNodeID? {
        selection.primarySceneNodeID
    }

    public var selectedTarget: SelectionTarget? {
        selection.primaryTarget
    }

    public var activeConstructionPlane: ConstructionPlaneSource? {
        document.activeConstructionPlane
    }

    public var selectedSceneNode: SceneNode? {
        guard let selectedSceneNodeID else {
            return nil
        }
        return document.productMetadata.sceneNodes[selectedSceneNodeID]
    }

    public init(
        document: DesignDocument = .empty(),
        selectedTool: ModelingTool = .select,
        polygonToolState: PolygonToolState = .standard,
        sketchInputState: SketchInputState = .standard,
        selection: SelectionModel = .empty,
        diagnostics: [EditorDiagnostic] = [],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) {
        self.store = CADDocumentStore(
            document: document,
            diagnostics: diagnostics,
            objectRegistry: objectRegistry
        )
        self.commandStack = CommandStack()
        self.selectedTool = selectedTool
        self.polygonToolState = polygonToolState
        self.sketchInputState = sketchInputState
        var initialSelection = selection
        initialSelection.pruneMissingReferences(in: document)
        self.selection = initialSelection
    }

    public func selectTool(_ tool: ModelingTool) {
        selectedTool = tool
        clearSketchInputStateIfNeeded(for: tool)
    }

    @discardableResult
    public func setPolygonSideCount(_ sideCount: Int) -> Bool {
        do {
            try polygonToolState.setSideCount(sideCount)
            return true
        } catch let failure as PolygonToolState.Failure {
            reportToolStatus(failure.message, severity: .warning)
            return false
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return false
        }
    }

    @discardableResult
    public func adjustPolygonSideCount(by delta: Int) -> Bool {
        do {
            try polygonToolState.adjustSideCount(by: delta)
            return true
        } catch let failure as PolygonToolState.Failure {
            reportToolStatus(failure.message, severity: .warning)
            return false
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return false
        }
    }

    @discardableResult
    public func setPolygonSizingMode(_ sizingMode: PolygonSizingMode) -> PolygonSizingMode {
        polygonToolState.setSizingMode(sizingMode)
        return polygonToolState.sizingMode
    }

    @discardableResult
    public func togglePolygonSizingMode() -> PolygonSizingMode {
        polygonToolState.toggleSizingMode()
        return polygonToolState.sizingMode
    }

    @discardableResult
    public func setPolygonInclinationMode(_ inclinationMode: PolygonInclinationMode) -> PolygonInclinationMode {
        polygonToolState.setInclinationMode(inclinationMode)
        return polygonToolState.inclinationMode
    }

    @discardableResult
    public func togglePolygonInclinationMode() -> PolygonInclinationMode {
        polygonToolState.toggleInclinationMode()
        return polygonToolState.inclinationMode
    }

    @discardableResult
    public func setPolygonCutsFaces(_ cutsFaces: Bool) -> Bool {
        polygonToolState.setCutsFaces(cutsFaces)
        return polygonToolState.cutsFaces
    }

    @discardableResult
    public func togglePolygonCutsFaces() -> Bool {
        polygonToolState.toggleCutsFaces()
        return polygonToolState.cutsFaces
    }

    @discardableResult
    public func setSketchAxisConstraint(_ axisConstraint: SketchAxisConstraint?) -> SketchAxisConstraint? {
        sketchInputState.setAxisConstraint(axisConstraint)
        return sketchInputState.axisConstraint
    }

    @discardableResult
    public func toggleSketchAxisConstraint(_ axisConstraint: SketchAxisConstraint) -> SketchAxisConstraint? {
        sketchInputState.toggleAxisConstraint(axisConstraint)
        return sketchInputState.axisConstraint
    }

    public func clearSketchAxisConstraint() {
        sketchInputState.clearAxisConstraint()
    }

    @discardableResult
    public func focusNextSketchDimensionInput(
        availableFocuses: [SketchDimensionInputFocus] = SketchDimensionInputFocus.allCases
    ) -> SketchDimensionInputFocus? {
        sketchInputState.focusNextDimensionInput(availableFocuses: availableFocuses)
    }

    public func clearSketchDimensionInputFocus() {
        sketchInputState.clearDimensionInputFocus()
    }

    @discardableResult
    public func setSketchDimensionInputLength(_ lengthMeters: Double?) -> Bool {
        do {
            try sketchInputState.setDimensionInputLengthMeters(lengthMeters)
            return true
        } catch let error as SketchDimensionInputValueError {
            reportToolStatus(error.message, severity: .warning)
            return false
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return false
        }
    }

    @discardableResult
    public func setSketchDimensionInputAngle(_ angleRadians: Double?) -> Bool {
        do {
            try sketchInputState.setDimensionInputAngleRadians(angleRadians)
            return true
        } catch let error as SketchDimensionInputValueError {
            reportToolStatus(error.message, severity: .warning)
            return false
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return false
        }
    }

    @discardableResult
    public func setSketchDimensionInputWidth(_ widthMeters: Double?) -> Bool {
        do {
            try sketchInputState.setDimensionInputWidthMeters(widthMeters)
            return true
        } catch let error as SketchDimensionInputValueError {
            reportToolStatus(error.message, severity: .warning)
            return false
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return false
        }
    }

    @discardableResult
    public func setSketchDimensionInputHeight(_ heightMeters: Double?) -> Bool {
        do {
            try sketchInputState.setDimensionInputHeightMeters(heightMeters)
            return true
        } catch let error as SketchDimensionInputValueError {
            reportToolStatus(error.message, severity: .warning)
            return false
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return false
        }
    }

    @discardableResult
    public func addSketchReferenceLineAnchor(at point: Point2D) -> Bool {
        guard point.x.isFinite, point.y.isFinite else {
            reportToolStatus(
                "Sketch reference line requires a finite model coordinate.",
                severity: .warning
            )
            return false
        }
        sketchInputState.addReferenceLineAnchor(SketchReferenceLineAnchor(point: point))
        return true
    }

    public func clearSketchReferenceLineAnchors() {
        sketchInputState.clearReferenceLineAnchors()
    }

    @discardableResult
    public func activateSelectedToolFromCanvas(
        targetSceneNodeID: SceneNodeID?,
        modelPoint: Point2D? = nil,
        modelWorldPoint: Point3D? = nil,
        sketchPlane: SketchPlane = .xy
    ) -> ModelingToolActivationResult {
        switch selectedTool {
        case .select:
            if let targetSceneNodeID {
                _ = selectSceneNode(targetSceneNodeID)
            } else {
                clearSelection()
            }
            return ModelingToolActivationResult(
                tool: .select,
                selectedSceneNodeID: selectedSceneNodeID
            )
        case .solid:
            if let targetSceneNodeID {
                guard let targetNode = document.productMetadata.sceneNodes[targetSceneNodeID],
                      targetNode.reference?.kind == .sketch else {
                    reportToolStatus(
                        "Solid tool requires a sketch profile canvas target.",
                        severity: .warning
                    )
                    return ModelingToolActivationResult(
                        tool: .solid,
                        selectedSceneNodeID: selectedSceneNodeID,
                        revealsDiagnostics: true
                    )
                }
                _ = selectSceneNode(targetSceneNodeID)
                let result = createDefaultSolid(fromSceneNode: targetSceneNodeID)
                if result != nil {
                    selectNewestSceneNode()
                    returnToSelectToolAfterSingleUse(result)
                }
                return ModelingToolActivationResult(
                    tool: .solid,
                    commandName: result?.commandName,
                    didMutate: result?.didMutate ?? false,
                    selectedSceneNodeID: selectedSceneNodeID,
                    revealsDiagnostics: result == nil
                )
            }
            guard let modelPoint else {
                return ModelingToolActivationResult(
                    tool: .solid,
                    selectedSceneNodeID: selectedSceneNodeID
                )
            }
            let result = createExtrudedRectangleFromCanvasClick(
                centerModelPoint: modelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .solid,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .sweep:
            let result = createSweepFromSelection(targetSceneNodeID: targetSceneNodeID)
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .sweep,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .measure:
            if let targetSceneNodeID {
                _ = selectSceneNode(targetSceneNodeID)
            } else {
                clearSelection()
            }
            reportMeasurementSummary()
            return ModelingToolActivationResult(
                tool: .measure,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: true
            )
        case .mesh:
            if let targetSceneNodeID {
                _ = selectSceneNode(targetSceneNodeID)
            }
            let result = perform(.validateDocument)
            reportMeshSummary()
            return ModelingToolActivationResult(
                tool: .mesh,
                commandName: result?.commandName,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: true
            )
        case .sketch:
            guard let modelPoint else {
                return ModelingToolActivationResult(
                    tool: .sketch,
                    selectedSceneNodeID: selectedSceneNodeID
                )
            }
            let result = createRectangleSketchFromCanvasClick(
                centerModelPoint: modelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .sketch,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .polygon:
            guard let modelPoint else {
                return ModelingToolActivationResult(
                    tool: .polygon,
                    selectedSceneNodeID: selectedSceneNodeID
                )
            }
            let result = createPolygonSketchFromCanvasClick(
                centerModelPoint: modelPoint,
                sketchPlane: sketchPlane,
                sides: polygonToolState.sideCount,
                sizingMode: polygonToolState.sizingMode,
                inclinationMode: polygonToolState.inclinationMode,
                centerWorldPoint: modelWorldPoint
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .polygon,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .arc:
            guard let modelPoint else {
                return ModelingToolActivationResult(
                    tool: .arc,
                    selectedSceneNodeID: selectedSceneNodeID
                )
            }
            let result = createArcSketchFromCanvasClick(
                centerModelPoint: modelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .arc,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .spline:
            guard let modelPoint else {
                return ModelingToolActivationResult(
                    tool: .spline,
                    selectedSceneNodeID: selectedSceneNodeID
                )
            }
            let result = createSplineSketchFromCanvasClick(
                centerModelPoint: modelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .spline,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .surface:
            guard let modelPoint else {
                return ModelingToolActivationResult(
                    tool: .surface,
                    selectedSceneNodeID: selectedSceneNodeID
                )
            }
            let result = createCircleSketchFromCanvasClick(
                centerModelPoint: modelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .surface,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .section:
            let result = createDefaultSectionPlane()
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .section,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        }
    }

    @discardableResult
    public func activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy,
        startWorldPoint: Point3D? = nil,
        endWorldPoint: Point3D? = nil
    ) -> ModelingToolActivationResult {
        switch selectedTool {
        case .sketch:
            let result = createRectangleSketchFromCanvasDrag(
                startModelPoint: startModelPoint,
                endModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .sketch,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .polygon:
            let result = createPolygonSketchFromCanvasDrag(
                centerModelPoint: startModelPoint,
                edgeModelPoint: endModelPoint,
                sketchPlane: sketchPlane,
                sides: polygonToolState.sideCount,
                sizingMode: polygonToolState.sizingMode,
                inclinationMode: polygonToolState.inclinationMode,
                centerWorldPoint: startWorldPoint,
                edgeWorldPoint: endWorldPoint
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .polygon,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .surface:
            let result = createCircleSketchFromCanvasDrag(
                centerModelPoint: startModelPoint,
                edgeModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .surface,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .arc:
            let result = createArcSketchFromCanvasDrag(
                centerModelPoint: startModelPoint,
                edgeModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .arc,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .spline:
            let result = createSplineSketchFromCanvasDrag(
                startModelPoint: startModelPoint,
                endModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .spline,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        case .solid:
            let result = createExtrudedRectangleFromCanvasDrag(
                startModelPoint: startModelPoint,
                endModelPoint: endModelPoint,
                sketchPlane: sketchPlane
            )
            if result != nil {
                selectNewestSceneNode()
                returnToSelectToolAfterSingleUse(result)
            }
            return ModelingToolActivationResult(
                tool: .solid,
                commandName: result?.commandName,
                didMutate: result?.didMutate ?? false,
                selectedSceneNodeID: selectedSceneNodeID,
                revealsDiagnostics: result == nil
            )
        default:
            return ModelingToolActivationResult(
                tool: selectedTool,
                selectedSceneNodeID: selectedSceneNodeID
            )
        }
    }

    @discardableResult
    public func activateTool(_ tool: ModelingTool) -> ModelingToolActivationResult {
        selectedTool = tool
        clearSketchInputStateIfNeeded(for: tool)
        return ModelingToolActivationResult(
            tool: tool,
            selectedSceneNodeID: selectedSceneNodeID
        )
    }

    private func returnToSelectToolAfterSingleUse(_ result: CommandExecutionResult?) {
        guard result?.didMutate == true else {
            return
        }
        selectedTool = .select
        clearSketchInputStateIfNeeded(for: .select)
    }

    private func clearSketchInputStateIfNeeded(for tool: ModelingTool) {
        guard !keepsSketchInputState(for: tool) else {
            return
        }
        sketchInputState.clearTransientInput()
    }

    private func keepsSketchInputState(for tool: ModelingTool) -> Bool {
        switch tool {
        case .sketch, .polygon, .arc, .spline, .solid, .surface:
            return true
        case .select, .sweep, .mesh, .measure, .section:
            return false
        }
    }

    @discardableResult
    public func perform(_ command: EditorCommand) -> CommandExecutionResult? {
        do {
            return try execute(command)
        } catch {
            record(error)
            return nil
        }
    }

    @discardableResult
    public func execute(
        _ command: EditorCommand,
        expectedGeneration: DocumentGeneration? = nil
    ) throws -> CommandExecutionResult {
        let resolvedCommand = try commandResolvingSelectionContext(command)
        let result = try commandStack.execute(
            resolvedCommand,
            in: store,
            expectedGeneration: expectedGeneration
        )
        selection.pruneMissingReferences(in: document)
        return result
    }

    private func commandResolvingSelectionContext(_ command: EditorCommand) throws -> EditorCommand {
        switch command {
        case .offsetCurve(let target, let distance, var options, let vertexHandle):
            guard options.supportTarget == nil,
                  case .edge = target.component,
                  let supportTarget = try supportFaceTargetResolvingSelectionContext(for: target) else {
                return command
            }
            options.supportTarget = supportTarget
            return .offsetCurve(
                target: target,
                distance: distance,
                options: options,
                vertexHandle: vertexHandle
            )
        default:
            return command
        }
    }

    private func supportFaceTargetResolvingSelectionContext(for edgeTarget: SelectionTarget) throws -> SelectionTarget? {
        let resolution = try EdgeOffsetSupportFaceResolver().resolve(
            edgeTarget: edgeTarget,
            selection: selection,
            document: document,
            objectRegistry: objectRegistry
        )
        if resolution.status == .ambiguous,
           let message = resolution.diagnosticMessage {
            throw EditorError(
                code: .commandInvalid,
                message: message
            )
        }
        return resolution.supportTarget
    }

    public func setDisplayUnit(_ unit: LengthDisplayUnit) {
        do {
            try execute(.setDisplayUnit(unit))
        } catch {
            record(error)
        }
    }

    public func setRulerConfiguration(_ configuration: RulerConfiguration) {
        do {
            try execute(.setRulerConfiguration(configuration))
        } catch {
            record(error)
        }
    }

    public func renameDocument(_ name: String) {
        do {
            try execute(.renameDocument(name: name))
        } catch {
            record(error)
        }
    }

    public func resetDocument(named name: String = "Untitled") {
        do {
            try execute(.resetDocument(name: name))
            selectedTool = .select
            selection.clearSelection()
            selection.clearHover()
        } catch {
            record(error)
        }
    }

    public func replaceProductMetadata(_ metadata: ProductMetadata) {
        do {
            try execute(.replaceProductMetadata(metadata))
        } catch {
            record(error)
        }
    }

    public func activeSketchPlane(fallback: SketchPlane = .xy) -> SketchPlane {
        activeConstructionPlane?.plane ?? fallback
    }

    @discardableResult
    public func createConstructionPlane(
        name: String,
        plane: SketchPlane,
        activates: Bool = true
    ) -> CommandExecutionResult? {
        perform(
            .createConstructionPlane(
                name: name,
                plane: plane,
                activates: activates
            )
        )
    }

    @discardableResult
    public func createConstructionPlaneFromTarget(
        name: String,
        target: SelectionTarget,
        activates: Bool = true
    ) -> CommandExecutionResult? {
        perform(
            .createConstructionPlaneFromTarget(
                name: name,
                target: target,
                activates: activates
            )
        )
    }

    @discardableResult
    public func createConstructionPlaneFromTarget(
        _ target: SelectionTarget,
        activates: Bool = true
    ) -> CommandExecutionResult? {
        createConstructionPlaneFromTarget(
            name: nextSceneNodeName(prefix: "Custom Plane"),
            target: target,
            activates: activates
        )
    }

    @discardableResult
    public func createConstructionPlaneFromTargets(
        name: String,
        targets: [SelectionTarget],
        viewNormal: Vector3D? = nil,
        activates: Bool = true
    ) -> CommandExecutionResult? {
        perform(
            .createConstructionPlaneFromTargets(
                name: name,
                targets: targets,
                viewNormal: viewNormal,
                activates: activates
            )
        )
    }

    @discardableResult
    public func createConstructionPlaneFromTargets(
        _ targets: [SelectionTarget],
        viewNormal: Vector3D? = nil,
        activates: Bool = true
    ) -> CommandExecutionResult? {
        createConstructionPlaneFromTargets(
            name: nextSceneNodeName(prefix: "Custom Plane"),
            targets: targets,
            viewNormal: viewNormal,
            activates: activates
        )
    }

    @discardableResult
    public func createViewAlignedConstructionPlane(
        name: String,
        origin: Point3D = .origin,
        viewNormal: Vector3D,
        activates: Bool = true
    ) -> CommandExecutionResult? {
        perform(
            .createViewAlignedConstructionPlane(
                name: name,
                origin: origin,
                viewNormal: viewNormal,
                activates: activates
            )
        )
    }

    @discardableResult
    public func createViewAlignedConstructionPlane(
        origin: Point3D = .origin,
        viewNormal: Vector3D,
        activates: Bool = true
    ) -> CommandExecutionResult? {
        createViewAlignedConstructionPlane(
            name: nextSceneNodeName(prefix: "Custom Plane"),
            origin: origin,
            viewNormal: viewNormal,
            activates: activates
        )
    }

    @discardableResult
    public func setActiveConstructionPlane(
        id: ConstructionPlaneSourceID?
    ) -> CommandExecutionResult? {
        perform(.setActiveConstructionPlane(id: id))
    }

    @discardableResult
    public func renameConstructionPlane(
        id: ConstructionPlaneSourceID,
        name: String
    ) -> CommandExecutionResult? {
        perform(.renameConstructionPlane(id: id, name: name))
    }

    @discardableResult
    public func setCurveCurvatureDisplay(
        target: SelectionTarget,
        isVisible: Bool? = nil,
        combScale: Double? = nil
    ) -> CommandExecutionResult? {
        perform(
            .setCurveCurvatureDisplay(
                target: target,
                isVisible: isVisible,
                combScale: combScale
            )
        )
    }

    public func deleteParameter(named name: String) {
        perform(.deleteParameter(name: name))
    }

    @discardableResult
    public func addSketchConstraint(
        featureID: FeatureID,
        constraint: SketchConstraint
    ) -> CommandExecutionResult? {
        perform(
            .addSketchConstraint(
                featureID: featureID,
                constraint: constraint
            )
        )
    }

    @discardableResult
    public func createBridgeCurve(
        featureID: FeatureID,
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint,
        continuity: BridgeCurveContinuity,
        trimsSourceCurves: Bool = false
    ) -> CommandExecutionResult? {
        perform(
            .createBridgeCurve(
                featureID: featureID,
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint,
                continuity: continuity,
                trimsSourceCurves: trimsSourceCurves
            )
        )
    }

    @discardableResult
    public func setBridgeCurveParameters(
        sourceID: BridgeCurveSourceID,
        firstEndpoint: BridgeCurveEndpoint? = nil,
        secondEndpoint: BridgeCurveEndpoint? = nil,
        continuity: BridgeCurveContinuity? = nil,
        trimsSourceCurves: Bool? = nil
    ) -> CommandExecutionResult? {
        perform(
            .setBridgeCurveParameters(
                sourceID: sourceID,
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint,
                continuity: continuity,
                trimsSourceCurves: trimsSourceCurves
            )
        )
    }

    @discardableResult
    public func createComponentDefinition(
        name: String,
        rootSceneNodeIDs: [SceneNodeID] = []
    ) -> CommandExecutionResult? {
        perform(
            .createComponentDefinition(
                name: name,
                rootSceneNodeIDs: rootSceneNodeIDs
            )
        )
    }

    @discardableResult
    public func createComponentInstance(
        name: String,
        definitionID: ComponentDefinitionID,
        localTransform: Transform3D = .identity
    ) -> CommandExecutionResult? {
        perform(
            .createComponentInstance(
                name: name,
                definitionID: definitionID,
                localTransform: localTransform
            )
        )
    }

    public func setSceneNodeVisibility(
        _ id: SceneNodeID,
        isVisible: Bool
    ) {
        perform(.setSceneNodeVisibility(id: id, isVisible: isVisible))
    }

    public func setSceneNodeLock(
        _ id: SceneNodeID,
        isLocked: Bool
    ) {
        perform(.setSceneNodeLock(id: id, isLocked: isLocked))
    }

    public func setSceneNodeTransform(
        _ id: SceneNodeID,
        localTransform: Transform3D
    ) {
        perform(
            .setSceneNodeTransform(
                id: id,
                localTransform: localTransform
            )
        )
    }

    public func setSceneNodeMaterial(
        _ id: SceneNodeID,
        materialID: MaterialID?
    ) {
        perform(
            .setSceneNodeMaterial(
                id: id,
                materialID: materialID
            )
        )
    }

    public func setSceneNodeObjectProperty(
        _ id: SceneNodeID,
        propertyID: ObjectPropertyID,
        value: ObjectPropertyValue?
    ) {
        perform(
            .setSceneNodeObjectProperty(
                id: id,
                propertyID: propertyID,
                value: value
            )
        )
    }

    public func setComponentInstanceVisibility(
        _ id: ComponentInstanceID,
        isVisible: Bool
    ) {
        perform(.setComponentInstanceVisibility(id: id, isVisible: isVisible))
    }

    public func setComponentInstanceLock(
        _ id: ComponentInstanceID,
        isLocked: Bool
    ) {
        perform(.setComponentInstanceLock(id: id, isLocked: isLocked))
    }

    public func setComponentInstanceTransform(
        _ id: ComponentInstanceID,
        localTransform: Transform3D
    ) {
        perform(
            .setComponentInstanceTransform(
                id: id,
                localTransform: localTransform
            )
        )
    }

    @discardableResult
    public func setPointDisplay(
        target: SelectionTarget,
        isVisible: Bool? = nil
    ) -> CommandExecutionResult? {
        perform(.setPointDisplay(target: target, isVisible: isVisible))
    }

    @discardableResult
    public func createDefaultRectangleSketch() -> CommandExecutionResult? {
        perform(
            .createRectangleSketch(
                name: nextFeatureName(prefix: "Rectangle Sketch"),
                plane: activeSketchPlane(),
                width: .length(40.0, .millimeter),
                height: .length(20.0, .millimeter)
            )
        )
    }

    @discardableResult
    public func createRectangleSketchFromCanvasClick(
        centerModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        guard centerModelPoint.x.isFinite,
              centerModelPoint.y.isFinite else {
            reportToolStatus(
                "Canvas rectangle placement requires a finite model coordinate.",
                severity: .warning
            )
            return nil
        }

        let widthMeters = activeSketchWidthInputMeters ?? LengthDisplayUnit.millimeter.meters(from: 40.0)
        let heightMeters = activeSketchHeightInputMeters ?? LengthDisplayUnit.millimeter.meters(from: 40.0)
        let halfWidthMeters = widthMeters / 2.0
        let halfHeightMeters = heightMeters / 2.0
        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        return perform(
            .createRectangleSketchFromCorners(
                name: nextFeatureName(prefix: "Rectangle Sketch"),
                plane: sketchPlane,
                firstCorner: SketchPoint(
                    x: lengthExpressionMeters(center.x - halfWidthMeters),
                    y: lengthExpressionMeters(center.y - halfHeightMeters)
                ),
                oppositeCorner: SketchPoint(
                    x: lengthExpressionMeters(center.x + halfWidthMeters),
                    y: lengthExpressionMeters(center.y + halfHeightMeters)
                )
            )
        )
    }

    @discardableResult
    public func createRectangleSketchFromCanvasDrag(
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        guard startModelPoint.x.isFinite,
              startModelPoint.y.isFinite,
              endModelPoint.x.isFinite,
              endModelPoint.y.isFinite else {
            reportToolStatus(
                "Canvas rectangle drag requires finite model coordinates.",
                severity: .warning
            )
            return nil
        }

        let start = sketchPoint2D(from: startModelPoint, on: sketchPlane)
        let end = sketchPoint2D(from: endModelPoint, on: sketchPlane)
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let widthMeters = activeSketchWidthInputMeters ?? abs(deltaX)
        let heightMeters = activeSketchHeightInputMeters ?? abs(deltaY)
        let endX = normalizedLengthMeters(start.x + signedDimension(widthMeters, following: deltaX))
        let endY = normalizedLengthMeters(start.y + signedDimension(heightMeters, following: deltaY))
        let minX = normalizedLengthMeters(min(start.x, endX))
        let minY = normalizedLengthMeters(min(start.y, endY))
        let maxX = normalizedLengthMeters(max(start.x, endX))
        let maxY = normalizedLengthMeters(max(start.y, endY))
        guard maxX > minX, maxY > minY else {
            reportToolStatus(
                "Canvas rectangle drag requires a non-zero width and height.",
                severity: .warning
            )
            return nil
        }

        return perform(
            .createRectangleSketchFromCorners(
                name: nextFeatureName(prefix: "Rectangle Sketch"),
                plane: sketchPlane,
                firstCorner: SketchPoint(
                    x: lengthExpressionMeters(minX),
                    y: lengthExpressionMeters(minY)
                ),
                oppositeCorner: SketchPoint(
                    x: lengthExpressionMeters(maxX),
                    y: lengthExpressionMeters(maxY)
                )
            )
        )
    }

    @discardableResult
    public func createDefaultCircleSketch() -> CommandExecutionResult? {
        perform(
            .createCircleSketch(
                name: nextFeatureName(prefix: "Circle Sketch"),
                plane: activeSketchPlane(),
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(12.0, .millimeter)
            )
        )
    }

    @discardableResult
    public func createSplineSketch(
        name: String,
        plane: SketchPlane,
        spline: SketchSpline
    ) -> CommandExecutionResult? {
        perform(
            .createSplineSketch(
                name: name,
                plane: plane,
                spline: spline
            )
        )
    }

    @discardableResult
    public func createCircleSketchFromCanvasClick(
        centerModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        guard centerModelPoint.x.isFinite,
              centerModelPoint.y.isFinite else {
            reportToolStatus(
                "Canvas circle placement requires a finite model coordinate.",
                severity: .warning
            )
            return nil
        }

        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        let radiusMeters = activeSketchLengthInputMeters ?? LengthDisplayUnit.millimeter.meters(from: 12.0)
        return perform(
            .createCircleSketch(
                name: nextFeatureName(prefix: "Circle Sketch"),
                plane: sketchPlane,
                center: SketchPoint(
                    x: .length(center.x, .meter),
                    y: .length(center.y, .meter)
                ),
                radius: .length(radiusMeters, .meter)
            )
        )
    }

    @discardableResult
    public func createCircleSketchFromCanvasDrag(
        centerModelPoint: Point2D,
        edgeModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        guard centerModelPoint.x.isFinite,
              centerModelPoint.y.isFinite,
              edgeModelPoint.x.isFinite,
              edgeModelPoint.y.isFinite else {
            reportToolStatus(
                "Canvas circle drag requires finite model coordinates.",
                severity: .warning
            )
            return nil
        }

        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        let edge = sketchPoint2D(from: edgeModelPoint, on: sketchPlane)
        let deltaX = edge.x - center.x
        let deltaY = edge.y - center.y
        let radius = activeSketchLengthInputMeters ?? sqrt(deltaX * deltaX + deltaY * deltaY)
        guard radius.isFinite, radius > 0.0 else {
            reportToolStatus(
                "Canvas circle drag requires a non-zero radius.",
                severity: .warning
            )
            return nil
        }

        return perform(
            .createCircleSketch(
                name: nextFeatureName(prefix: "Circle Sketch"),
                plane: sketchPlane,
                center: SketchPoint(
                    x: .length(center.x, .meter),
                    y: .length(center.y, .meter)
                ),
                radius: .length(radius, .meter)
            )
        )
    }

    @discardableResult
    public func createPolygonSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        sides: Int,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        rotationAngle: CADExpression = .angle(0.0, .radian)
    ) -> CommandExecutionResult? {
        let result = perform(
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
        rememberPolygonToolState(
            sideCount: sides,
            sizingMode: sizingMode,
            inclinationMode: inclinationMode,
            cutsFaces: polygonToolState.cutsFaces,
            after: result
        )
        return result
    }

    @discardableResult
    public func createPolygonSketchFromCanvasClick(
        centerModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy,
        sides: Int = CanvasSketchCurveDrafts.defaultPolygonSides,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        centerWorldPoint: Point3D? = nil
    ) -> CommandExecutionResult? {
        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        if polygonToolState.cutsFaces {
            guard let context = selectedFaceKnifeDraftContext() else {
                return nil
            }
            let faceCenter = faceKnifeLocalPoint(
                from: centerWorldPoint,
                fallback: center,
                coordinateSystem: context.coordinateSystem
            )
            let draft: CanvasSketchCurveDrafts.Polygon
            do {
                draft = try CanvasSketchCurveDrafts.polygon(
                    centeredAt: faceCenter,
                    sides: sides,
                    sizingMode: sizingMode,
                    inclinationMode: inclinationMode,
                    radiusMeters: activeSketchLengthInputMeters,
                    rotationAngleRadians: activeSketchAngleInputRadians
                )
            } catch let failure as CanvasSketchCurveDrafts.Failure {
                reportToolStatus(failure.message, severity: .warning)
                return nil
            } catch {
                reportToolStatus(String(describing: error), severity: .warning)
                return nil
            }
            let result = createFaceKnifeFromPolygonDraft(
                draft,
                target: context.target,
                coordinateSystem: context.coordinateSystem
            )
            rememberPolygonToolState(
                sideCount: draft.sides,
                sizingMode: draft.sizingMode,
                inclinationMode: draft.inclinationMode,
                cutsFaces: polygonToolState.cutsFaces,
                after: result
            )
            return result
        }

        let draft: CanvasSketchCurveDrafts.Polygon
        do {
            draft = try CanvasSketchCurveDrafts.polygon(
                centeredAt: center,
                sides: sides,
                sizingMode: sizingMode,
                inclinationMode: inclinationMode,
                radiusMeters: activeSketchLengthInputMeters,
                rotationAngleRadians: activeSketchAngleInputRadians
            )
        } catch let failure as CanvasSketchCurveDrafts.Failure {
            reportToolStatus(failure.message, severity: .warning)
            return nil
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return nil
        }

        let result = perform(
            .createPolygonSketch(
                name: nextFeatureName(prefix: "Polygon Sketch"),
                plane: sketchPlane,
                center: sketchPoint(draft.center),
                radius: lengthExpressionMeters(draft.radiusMeters),
                sides: draft.sides,
                sizingMode: draft.sizingMode,
                inclinationMode: draft.inclinationMode,
                rotationAngle: angleExpressionRadians(draft.rotationAngleRadians)
            )
        )
        rememberPolygonToolState(
            sideCount: draft.sides,
            sizingMode: draft.sizingMode,
            inclinationMode: draft.inclinationMode,
            cutsFaces: polygonToolState.cutsFaces,
            after: result
        )
        return result
    }

    @discardableResult
    public func createPolygonSketchFromCanvasDrag(
        centerModelPoint: Point2D,
        edgeModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy,
        sides: Int = CanvasSketchCurveDrafts.defaultPolygonSides,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        centerWorldPoint: Point3D? = nil,
        edgeWorldPoint: Point3D? = nil
    ) -> CommandExecutionResult? {
        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        let edge = sketchPoint2D(from: edgeModelPoint, on: sketchPlane)
        if polygonToolState.cutsFaces {
            guard let context = selectedFaceKnifeDraftContext() else {
                return nil
            }
            let faceCenter = faceKnifeLocalPoint(
                from: centerWorldPoint,
                fallback: center,
                coordinateSystem: context.coordinateSystem
            )
            let faceEdge = faceKnifeLocalPoint(
                from: edgeWorldPoint,
                fallback: edge,
                coordinateSystem: context.coordinateSystem
            )
            let draft: CanvasSketchCurveDrafts.Polygon
            do {
                draft = try CanvasSketchCurveDrafts.polygon(
                    fromCenter: faceCenter,
                    toRadiusPoint: faceEdge,
                    sides: sides,
                    sizingMode: sizingMode,
                    inclinationMode: inclinationMode,
                    radiusMeters: activeSketchLengthInputMeters,
                    rotationAngleRadians: activeSketchAngleInputRadians
                )
            } catch let failure as CanvasSketchCurveDrafts.Failure {
                reportToolStatus(failure.message, severity: .warning)
                return nil
            } catch {
                reportToolStatus(String(describing: error), severity: .warning)
                return nil
            }
            let result = createFaceKnifeFromPolygonDraft(
                draft,
                target: context.target,
                coordinateSystem: context.coordinateSystem
            )
            rememberPolygonToolState(
                sideCount: draft.sides,
                sizingMode: draft.sizingMode,
                inclinationMode: draft.inclinationMode,
                cutsFaces: polygonToolState.cutsFaces,
                after: result
            )
            return result
        }

        let draft: CanvasSketchCurveDrafts.Polygon
        do {
            draft = try CanvasSketchCurveDrafts.polygon(
                fromCenter: center,
                toRadiusPoint: edge,
                sides: sides,
                sizingMode: sizingMode,
                inclinationMode: inclinationMode,
                radiusMeters: activeSketchLengthInputMeters,
                rotationAngleRadians: activeSketchAngleInputRadians
            )
        } catch let failure as CanvasSketchCurveDrafts.Failure {
            reportToolStatus(failure.message, severity: .warning)
            return nil
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return nil
        }

        let result = perform(
            .createPolygonSketch(
                name: nextFeatureName(prefix: "Polygon Sketch"),
                plane: sketchPlane,
                center: sketchPoint(draft.center),
                radius: lengthExpressionMeters(draft.radiusMeters),
                sides: draft.sides,
                sizingMode: draft.sizingMode,
                inclinationMode: draft.inclinationMode,
                rotationAngle: angleExpressionRadians(draft.rotationAngleRadians)
            )
        )
        rememberPolygonToolState(
            sideCount: draft.sides,
            sizingMode: draft.sizingMode,
            inclinationMode: draft.inclinationMode,
            cutsFaces: polygonToolState.cutsFaces,
            after: result
        )
        return result
    }

    @discardableResult
    public func createFaceKnife(
        name: String,
        target: SelectionTarget,
        loop: [Point3D]
    ) -> CommandExecutionResult? {
        perform(
            .createFaceKnife(
                name: name,
                target: target,
                loop: loop
            )
        )
    }

    private func selectedFaceKnifeDraftContext() -> (
        target: SelectionTarget,
        coordinateSystem: SketchPlaneCoordinateSystem
    )? {
        guard let target = selectedTarget,
              case .face = target.component else {
            reportToolStatus("Polygon Knife requires a selected generated face target.", severity: .warning)
            return nil
        }
        do {
            // Knife drafts are supported by the selected target face, not by the active construction plane.
            let targetPlane = try ConstructionPlaneTargetResolver().plane(
                alignedTo: target,
                in: document,
                objectRegistry: objectRegistry
            )
            return (
                target: target,
                coordinateSystem: try SketchPlaneCoordinateSystem(plane: targetPlane)
            )
        } catch {
            reportToolStatus("Polygon Knife requires a selected generated planar face target: \(error).", severity: .warning)
            return nil
        }
    }

    private func faceKnifeLocalPoint(
        from worldPoint: Point3D?,
        fallback: Point2D,
        coordinateSystem: SketchPlaneCoordinateSystem
    ) -> Point2D {
        guard let worldPoint else {
            return fallback
        }
        let projection = coordinateSystem.project(worldPoint)
        guard abs(projection.depth) <= 1.0e-7 else {
            return fallback
        }
        return projection.point
    }

    private func createFaceKnifeFromPolygonDraft(
        _ draft: CanvasSketchCurveDrafts.Polygon,
        target: SelectionTarget,
        coordinateSystem: SketchPlaneCoordinateSystem
    ) -> CommandExecutionResult? {
        let loop = draft.vertices.map { coordinateSystem.point(from: $0) }
        return createFaceKnife(
            name: nextFeatureName(prefix: "Face Knife"),
            target: target,
            loop: loop
        )
    }

    private func rememberPolygonToolState(
        sideCount: Int,
        sizingMode: PolygonSizingMode,
        inclinationMode: PolygonInclinationMode,
        cutsFaces: Bool,
        after result: CommandExecutionResult?
    ) {
        guard result?.didMutate == true else {
            return
        }
        do {
            polygonToolState = try PolygonToolState(
                sideCount: sideCount,
                sizingMode: sizingMode,
                inclinationMode: inclinationMode,
                cutsFaces: cutsFaces
            )
        } catch let failure as PolygonToolState.Failure {
            reportToolStatus(failure.message, severity: .warning)
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
        }
    }

    @discardableResult
    public func createArcSketchFromCanvasClick(
        centerModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        let draft: CanvasSketchCurveDrafts.Arc
        do {
            draft = try CanvasSketchCurveDrafts.arc(
                centeredAt: center,
                radiusMeters: activeSketchLengthInputMeters,
                spanAngleRadians: activeSketchAngleInputRadians
            )
        } catch let failure as CanvasSketchCurveDrafts.Failure {
            reportToolStatus(failure.message, severity: .warning)
            return nil
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return nil
        }

        return perform(
            .createArcSketch(
                name: nextFeatureName(prefix: "Arc Sketch"),
                plane: sketchPlane,
                center: sketchPoint(x: draft.center.x, y: draft.center.y),
                radius: lengthExpressionMeters(draft.radiusMeters),
                startAngle: .angle(draft.startAngleRadians, .radian),
                endAngle: .angle(draft.endAngleRadians, .radian)
            )
        )
    }

    @discardableResult
    public func createArcSketchFromCanvasDrag(
        centerModelPoint: Point2D,
        edgeModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        let edge = sketchPoint2D(from: edgeModelPoint, on: sketchPlane)
        let draft: CanvasSketchCurveDrafts.Arc
        do {
            draft = try CanvasSketchCurveDrafts.arc(
                fromCenter: center,
                toRadiusPoint: edge,
                radiusMeters: activeSketchLengthInputMeters,
                spanAngleRadians: activeSketchAngleInputRadians
            )
        } catch let failure as CanvasSketchCurveDrafts.Failure {
            reportToolStatus(failure.message, severity: .warning)
            return nil
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return nil
        }

        return perform(
            .createArcSketch(
                name: nextFeatureName(prefix: "Arc Sketch"),
                plane: sketchPlane,
                center: sketchPoint(x: draft.center.x, y: draft.center.y),
                radius: lengthExpressionMeters(draft.radiusMeters),
                startAngle: .angle(draft.startAngleRadians, .radian),
                endAngle: .angle(draft.endAngleRadians, .radian)
            )
        )
    }

    private var activeSketchLengthInputMeters: Double? {
        guard sketchInputState.dimensionInputFocus == .length,
              let lengthMeters = sketchInputState.dimensionInputLengthMeters,
              lengthMeters.isFinite,
              lengthMeters > 0.0 else {
            return nil
        }
        return CADInputValueNormalizer.standard.lengthMeters(lengthMeters)
    }

    private var activeSketchAngleInputRadians: Double? {
        guard sketchInputState.dimensionInputFocus == .angle,
              let angleRadians = sketchInputState.dimensionInputAngleRadians,
              angleRadians.isFinite else {
            return nil
        }
        return CADInputValueNormalizer.standard.angleRadians(angleRadians)
    }

    private var activeSketchWidthInputMeters: Double? {
        guard isRectangleDimensionInputActive,
              let widthMeters = sketchInputState.dimensionInputWidthMeters,
              widthMeters.isFinite,
              widthMeters > 0.0 else {
            return nil
        }
        return CADInputValueNormalizer.standard.lengthMeters(widthMeters)
    }

    private var activeSketchHeightInputMeters: Double? {
        guard isRectangleDimensionInputActive,
              let heightMeters = sketchInputState.dimensionInputHeightMeters,
              heightMeters.isFinite,
              heightMeters > 0.0 else {
            return nil
        }
        return CADInputValueNormalizer.standard.lengthMeters(heightMeters)
    }

    private var isRectangleDimensionInputActive: Bool {
        switch sketchInputState.dimensionInputFocus {
        case .width, .height:
            return true
        case .length, .angle, nil:
            return false
        }
    }

    private func signedDimension(_ dimension: Double, following delta: Double) -> Double {
        delta < 0.0 ? -dimension : dimension
    }

    @discardableResult
    public func createSplineSketchFromCanvasClick(
        centerModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        let draft: CanvasSketchCurveDrafts.Spline
        do {
            draft = try CanvasSketchCurveDrafts.spline(
                centeredAt: center
            )
        } catch let failure as CanvasSketchCurveDrafts.Failure {
            reportToolStatus(failure.message, severity: .warning)
            return nil
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return nil
        }

        return perform(
            .createSplineSketch(
                name: nextFeatureName(prefix: "Spline Sketch"),
                plane: sketchPlane,
                spline: SketchSpline(
                    controlPoints: draft.controlPoints.map(sketchPoint)
                )
            )
        )
    }

    @discardableResult
    public func createSplineSketchFromCanvasDrag(
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        let start = sketchPoint2D(from: startModelPoint, on: sketchPlane)
        let end = sketchPoint2D(from: endModelPoint, on: sketchPlane)
        let draft: CanvasSketchCurveDrafts.Spline
        do {
            draft = try CanvasSketchCurveDrafts.spline(
                from: start,
                to: end
            )
        } catch let failure as CanvasSketchCurveDrafts.Failure {
            reportToolStatus(failure.message, severity: .warning)
            return nil
        } catch {
            reportToolStatus(String(describing: error), severity: .warning)
            return nil
        }

        return perform(
            .createSplineSketch(
                name: nextFeatureName(prefix: "Spline Sketch"),
                plane: sketchPlane,
                spline: SketchSpline(
                    controlPoints: draft.controlPoints.map(sketchPoint)
                )
            )
        )
    }

    @discardableResult
    public func createDefaultExtrudedRectangle() -> CommandExecutionResult? {
        perform(
            .createExtrudedRectangle(
                name: nextFeatureName(prefix: "Box"),
                plane: activeSketchPlane(),
                width: .length(40.0, .millimeter),
                height: .length(20.0, .millimeter),
                depth: .length(10.0, .millimeter),
                direction: .normal
            )
        )
    }

    @discardableResult
    public func createExtrudedRectangleFromCanvasClick(
        centerModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        guard centerModelPoint.x.isFinite,
              centerModelPoint.y.isFinite else {
            reportToolStatus(
                "Canvas solid placement requires a finite model coordinate.",
                severity: .warning
            )
            return nil
        }

        let halfSideMeters = LengthDisplayUnit.millimeter.meters(from: 20.0)
        let sideMeters = halfSideMeters * 2.0
        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        return perform(
            .createExtrudedRectangleFromCorners(
                name: nextFeatureName(prefix: "Box"),
                plane: sketchPlane,
                firstCorner: SketchPoint(
                    x: lengthExpressionMeters(center.x - halfSideMeters),
                    y: lengthExpressionMeters(center.y - halfSideMeters)
                ),
                oppositeCorner: SketchPoint(
                    x: lengthExpressionMeters(center.x + halfSideMeters),
                    y: lengthExpressionMeters(center.y + halfSideMeters)
                ),
                depth: lengthExpressionMeters(sideMeters),
                direction: .normal
            )
        )
    }

    @discardableResult
    public func createExtrudedRectangleFromCanvasDrag(
        startModelPoint: Point2D,
        endModelPoint: Point2D,
        sketchPlane: SketchPlane = .xy
    ) -> CommandExecutionResult? {
        guard startModelPoint.x.isFinite,
              startModelPoint.y.isFinite,
              endModelPoint.x.isFinite,
              endModelPoint.y.isFinite else {
            reportToolStatus(
                "Canvas solid drag requires finite model coordinates.",
                severity: .warning
            )
            return nil
        }

        let start = sketchPoint2D(from: startModelPoint, on: sketchPlane)
        let end = sketchPoint2D(from: endModelPoint, on: sketchPlane)
        let minX = normalizedLengthMeters(min(start.x, end.x))
        let minY = normalizedLengthMeters(min(start.y, end.y))
        let maxX = normalizedLengthMeters(max(start.x, end.x))
        let maxY = normalizedLengthMeters(max(start.y, end.y))
        guard maxX > minX, maxY > minY else {
            reportToolStatus(
                "Canvas solid drag requires a non-zero width and height.",
                severity: .warning
            )
            return nil
        }

        return perform(
            .createExtrudedRectangleFromCorners(
                name: nextFeatureName(prefix: "Box"),
                plane: sketchPlane,
                firstCorner: SketchPoint(
                    x: lengthExpressionMeters(minX),
                    y: lengthExpressionMeters(minY)
                ),
                oppositeCorner: SketchPoint(
                    x: lengthExpressionMeters(maxX),
                    y: lengthExpressionMeters(maxY)
                ),
                depth: .length(10.0, .millimeter),
                direction: .normal
            )
        )
    }

    @discardableResult
    public func createDefaultSolid() -> CommandExecutionResult? {
        createDefaultSolid(fromSceneNode: selectedSceneNodeID)
    }

    @discardableResult
    public func createDefaultSolid(fromSceneNode sceneNodeID: SceneNodeID?) -> CommandExecutionResult? {
        guard let sceneNodeID,
              let sceneNode = document.productMetadata.sceneNodes[sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            return createDefaultExtrudedRectangle()
        }

        return perform(
            .extrudeProfile(
                name: nextFeatureName(prefix: "\(sceneNode.name) Body"),
                profile: ProfileReference(featureID: featureID),
                distance: .length(10.0, .millimeter),
                direction: .normal
            )
        )
    }

    @discardableResult
    public func createSweep(
        name: String,
        profiles: [ProfileReference],
        path: SweepPathReference,
        guides: [SweepGuideReference] = [],
        targets: [SweepTargetReference] = [],
        options: SweepOptions = SweepOptions()
    ) -> CommandExecutionResult? {
        perform(
            .createSweep(
                name: name,
                profiles: profiles,
                path: path,
                guides: guides,
                targets: targets,
                options: options
            )
        )
    }

    @discardableResult
    public func createRevolve(
        name: String,
        profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree))
    ) -> CommandExecutionResult? {
        perform(
            .createRevolve(
                name: name,
                profile: profile,
                axis: axis,
                angle: angle
            )
        )
    }

    @discardableResult
    public func createPolySplineSurface(
        name: String,
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions()
    ) -> CommandExecutionResult? {
        perform(
            .createPolySplineSurface(
                name: name,
                sourceMesh: sourceMesh,
                options: options
            )
        )
    }

    @discardableResult
    public func movePolySplineSurfaceVertex(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .movePolySplineSurfaceVertex(
                target: target,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaZ: deltaZ
            )
        )
    }

    @discardableResult
    public func slidePolySplineSurfaceVertices(
        targets: [SelectionTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .slidePolySplineSurfaceVertices(
                targets: targets,
                direction: direction,
                distance: distance
            )
        )
    }

    @discardableResult
    public func slideSelectedPolySplineSurfaceVertices(
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression
    ) -> CommandExecutionResult? {
        let targets = selection.selectedTargets.filter { target in
            if case .vertex = target.component {
                return true
            }
            return false
        }
        guard targets.isEmpty == false else {
            reportToolStatus(
                "PolySpline surface vertex slide requires generated vertex selections.",
                severity: .warning
            )
            return nil
        }
        return slidePolySplineSurfaceVertices(
            targets: targets,
            direction: direction,
            distance: distance
        )
    }

    @discardableResult
    public func moveSelectedPolySplineSurfaceVertex(
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression
    ) -> CommandExecutionResult? {
        guard let selectedTarget,
              case .vertex = selectedTarget.component else {
            reportToolStatus("PolySpline surface vertex move requires a generated vertex selection.", severity: .warning)
            return nil
        }
        return movePolySplineSurfaceVertex(
            target: selectedTarget,
            deltaX: deltaX,
            deltaY: deltaY,
            deltaZ: deltaZ
        )
    }

    @discardableResult
    public func createSweepFromSelection(
        targetSceneNodeID: SceneNodeID? = nil,
        name: String? = nil,
        options: SweepOptions = SweepOptions()
    ) -> CommandExecutionResult? {
        do {
            let request = try sweepRequestFromSelection(
                targetSceneNodeID: targetSceneNodeID,
                name: name,
                options: options
            )
            return createSweep(
                name: request.name,
                profiles: [ProfileReference(featureID: request.profileFeatureID)],
                path: SweepPathReference(featureID: request.pathFeatureID),
                guides: request.guideFeatureIDs.map { SweepGuideReference(featureID: $0) },
                targets: [],
                options: request.options
            )
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return nil
        }
    }

    public func sweepSelectionPreview(targetSceneNodeID: SceneNodeID? = nil) -> SweepSelectionPreview {
        do {
            return try sweepSelectionResolution(
                targetSceneNodeID: targetSceneNodeID,
                name: nil,
                options: SweepOptions()
            ).preview
        } catch {
            return SweepSelectionPreview(
                status: .invalid,
                message: error.localizedDescription
            )
        }
    }

    private struct SweepSelectionRequest {
        var name: String
        var profileFeatureID: FeatureID
        var pathFeatureID: FeatureID
        var guideFeatureIDs: [FeatureID]
        var options: SweepOptions
    }

    private struct SweepSelectionResolution {
        var name: String
        var profileFeatureID: FeatureID?
        var pathFeatureID: FeatureID?
        var guideFeatureIDs: [FeatureID]
        var options: SweepOptions

        var preview: SweepSelectionPreview {
            guard let profileFeatureID else {
                return SweepSelectionPreview(
                    status: .missingProfile,
                    pathFeatureID: pathFeatureID,
                    guideFeatureIDs: guideFeatureIDs,
                    message: "Sweep requires a closed profile source."
                )
            }
            guard let pathFeatureID else {
                return SweepSelectionPreview(
                    status: .missingPath,
                    profileFeatureID: profileFeatureID,
                    guideFeatureIDs: guideFeatureIDs,
                    message: "Sweep requires a separate path curve source."
                )
            }
            return SweepSelectionPreview(
                status: .ready,
                profileFeatureID: profileFeatureID,
                pathFeatureID: pathFeatureID,
                guideFeatureIDs: guideFeatureIDs,
                message: "Sweep source is ready with \(guideFeatureIDs.count) guide curve(s)."
            )
        }

        func request() throws -> SweepSelectionRequest {
            guard let profileFeatureID,
                  let pathFeatureID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sweep tool requires one closed profile source, one separate path curve source, and optional guide curve selections."
                )
            }
            return SweepSelectionRequest(
                name: name,
                profileFeatureID: profileFeatureID,
                pathFeatureID: pathFeatureID,
                guideFeatureIDs: guideFeatureIDs,
                options: options
            )
        }
    }

    private struct SweepSourceCandidate {
        var isTarget: Bool
        var profileFeatureID: FeatureID?
        var pathFeatureID: FeatureID?
    }

    private struct SweepCandidateSceneNode {
        var id: SceneNodeID
        var isTarget: Bool
    }

    private func sweepRequestFromSelection(
        targetSceneNodeID: SceneNodeID?,
        name: String?,
        options: SweepOptions
    ) throws -> SweepSelectionRequest {
        try sweepSelectionResolution(
            targetSceneNodeID: targetSceneNodeID,
            name: name,
            options: options
        ).request()
    }

    private func sweepSelectionResolution(
        targetSceneNodeID: SceneNodeID?,
        name: String?,
        options: SweepOptions
    ) throws -> SweepSelectionResolution {
        var candidates: [SweepSourceCandidate] = []
        for sceneNode in orderedSweepCandidateSceneNodes(targetSceneNodeID: targetSceneNodeID) {
            if let candidate = try sweepSourceCandidate(for: sceneNode) {
                candidates.append(candidate)
            }
        }
        let profileFeatureID = candidates.compactMap(\.profileFeatureID).first
        let curveFeatureIDs = uniqueFeatureIDs(
            candidates.compactMap(\.pathFeatureID).filter { featureID in
                featureID != profileFeatureID
            }
        )
        let targetCurveFeatureID = candidates.last { candidate in
            candidate.isTarget
        }?.pathFeatureID.flatMap { featureID in
            featureID == profileFeatureID ? nil : featureID
        }
        let pathFeatureID = targetCurveFeatureID ?? curveFeatureIDs.last
        let guideFeatureIDs = uniqueFeatureIDs(
            curveFeatureIDs.filter { featureID in
                featureID != pathFeatureID
            }
        )
        return SweepSelectionResolution(
            name: name ?? nextFeatureName(prefix: "Sweep"),
            profileFeatureID: profileFeatureID,
            pathFeatureID: pathFeatureID,
            guideFeatureIDs: guideFeatureIDs,
            options: options
        )
    }

    private func orderedSweepCandidateSceneNodes(targetSceneNodeID: SceneNodeID?) -> [SweepCandidateSceneNode] {
        var sceneNodes = selection.selectedSceneNodeIDs.map { sceneNodeID in
            SweepCandidateSceneNode(id: sceneNodeID, isTarget: false)
        }
        if let targetSceneNodeID {
            sceneNodes.append(SweepCandidateSceneNode(id: targetSceneNodeID, isTarget: true))
        }
        var orderedSceneNodes: [SweepCandidateSceneNode] = []
        var seenIDs: Set<SceneNodeID> = []
        for sceneNode in sceneNodes {
            if let existingIndex = orderedSceneNodes.firstIndex(where: { $0.id == sceneNode.id }) {
                orderedSceneNodes[existingIndex].isTarget = orderedSceneNodes[existingIndex].isTarget || sceneNode.isTarget
                continue
            }
            guard seenIDs.insert(sceneNode.id).inserted else {
                continue
            }
            orderedSceneNodes.append(sceneNode)
        }
        return orderedSceneNodes
    }

    private func sweepSourceCandidate(for candidateSceneNode: SweepCandidateSceneNode) throws -> SweepSourceCandidate? {
        let sceneNodeID = candidateSceneNode.id
        guard let sceneNode = document.productMetadata.sceneNodes[sceneNodeID] else {
            return nil
        }
        let objectProfileID = sceneNode.object?.sourceProfileFeatureID
        let sketchFeatureID = sceneNode.reference?.kind == .sketch ? sceneNode.reference?.featureID : nil
        var profileFeatureID: FeatureID?
        for candidateFeatureID in [objectProfileID, sketchFeatureID].compactMap({ $0 }) {
            if try isSupportedSweepProfileFeature(candidateFeatureID) {
                profileFeatureID = candidateFeatureID
                break
            }
        }
        let pathFeatureID: FeatureID?
        if let sketchFeatureID,
           isSweepPathFeature(sketchFeatureID) {
            pathFeatureID = sketchFeatureID
        } else {
            pathFeatureID = nil
        }
        guard profileFeatureID != nil || pathFeatureID != nil else {
            return nil
        }
        return SweepSourceCandidate(
            isTarget: candidateSceneNode.isTarget,
            profileFeatureID: profileFeatureID,
            pathFeatureID: pathFeatureID
        )
    }

    private func isSupportedSweepProfileFeature(_ featureID: FeatureID) throws -> Bool {
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              feature.outputs.contains(where: { $0.role == .profile }),
              case let .sketch(sketch) = feature.operation else {
            return false
        }
        do {
            let parameters = try ParameterResolver().resolve(document.cadDocument.parameters)
            let profiles = try SketchProfileExtractor().extractProfiles(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: parameters
            )
            return profiles.isEmpty == false
        } catch {
            if error is SketchError || error is GeometryError || error is UnitError {
                return false
            }
            throw error
        }
    }

    private func isSweepPathFeature(_ featureID: FeatureID) -> Bool {
        guard let feature = document.cadDocument.designGraph.nodes[featureID],
              feature.outputs.contains(where: { $0.role == .curve }),
              case .sketch = feature.operation else {
            return false
        }
        return true
    }

    private func uniqueFeatureIDs(_ featureIDs: [FeatureID]) -> [FeatureID] {
        var uniqueFeatureIDs: [FeatureID] = []
        var seenFeatureIDs: Set<FeatureID> = []
        for featureID in featureIDs {
            guard seenFeatureIDs.insert(featureID).inserted else {
                continue
            }
            uniqueFeatureIDs.append(featureID)
        }
        return uniqueFeatureIDs
    }

    public func setExtrudeDistance(
        featureID: FeatureID,
        distance: CADExpression
    ) {
        perform(
            .setExtrudeDistance(
                featureID: featureID,
                distance: distance
            )
        )
    }

    public func setCubeDimensions(
        featureID: FeatureID,
        sizeX: CADExpression,
        sizeY: CADExpression,
        sizeZ: CADExpression
    ) {
        perform(
            .setCubeDimensions(
                featureID: featureID,
                sizeX: sizeX,
                sizeY: sizeY,
                sizeZ: sizeZ
            )
        )
    }

    public func setCylinderDimensions(
        featureID: FeatureID,
        radius: CADExpression,
        sizeY: CADExpression
    ) {
        perform(
            .setCylinderDimensions(
                featureID: featureID,
                radius: radius,
                sizeY: sizeY
            )
        )
    }

    @discardableResult
    public func setObjectDimension(
        target: SelectionTarget,
        kind: ObjectDimensionKind,
        value: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .setObjectDimension(
                target: target,
                kind: kind,
                value: value
            )
        )
    }

    @discardableResult
    public func offsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        options: OffsetCurveOptions = OffsetCurveOptions(),
        vertexHandle: SketchEntityPointHandle? = nil
    ) -> CommandExecutionResult? {
        perform(
            .offsetCurve(
                target: target,
                distance: distance,
                options: options,
                vertexHandle: vertexHandle
            )
        )
    }

    @discardableResult
    public func offsetSketchVertex(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        distance: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .offsetSketchVertex(
                target: target,
                handle: handle,
                distance: distance
            )
        )
    }

    @discardableResult
    public func offsetRegions(
        targets: [SelectionTarget],
        distance: CADExpression,
        options: OffsetCurveOptions = OffsetCurveOptions(),
        combinesRegions: Bool = false
    ) -> CommandExecutionResult? {
        perform(
            .offsetRegions(
                targets: targets,
                distance: distance,
                options: options,
                combinesRegions: combinesRegions
            )
        )
    }

    @discardableResult
    public func offsetBodyFace(
        target: SelectionTarget,
        distance: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .offsetBodyFace(
                target: target,
                distance: distance
            )
        )
    }

    @discardableResult
    public func offsetSelectedBodyFace(distance: CADExpression) -> CommandExecutionResult? {
        guard let selectedTarget else {
            reportToolStatus("Face offset requires a face selection.", severity: .warning)
            return nil
        }
        return offsetBodyFace(target: selectedTarget, distance: distance)
    }

    @discardableResult
    public func chamferBodyEdges(
        targets: [SelectionTarget],
        distance: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .chamferBodyEdges(
                targets: targets,
                distance: distance
            )
        )
    }

    @discardableResult
    public func chamferSelectedBodyEdges(distance: CADExpression) -> CommandExecutionResult? {
        let selectedEdgeTargets = selection.selectedTargets.filter { target in
            if case .edge = target.component {
                return true
            }
            return false
        }
        guard !selectedEdgeTargets.isEmpty else {
            reportToolStatus("Edge chamfer requires edge selections.", severity: .warning)
            return nil
        }
        return chamferBodyEdges(targets: selectedEdgeTargets, distance: distance)
    }

    @discardableResult
    public func filletBodyEdges(
        targets: [SelectionTarget],
        radius: CADExpression,
        segmentCount: Int = 8
    ) -> CommandExecutionResult? {
        perform(
            .filletBodyEdges(
                targets: targets,
                radius: radius,
                segmentCount: segmentCount
            )
        )
    }

    @discardableResult
    public func filletSelectedBodyEdges(
        radius: CADExpression,
        segmentCount: Int = 8
    ) -> CommandExecutionResult? {
        let selectedEdgeTargets = selection.selectedTargets.filter { target in
            if case .edge = target.component {
                return true
            }
            return false
        }
        guard !selectedEdgeTargets.isEmpty else {
            reportToolStatus("Edge fillet requires edge selections.", severity: .warning)
            return nil
        }
        return filletBodyEdges(
            targets: selectedEdgeTargets,
            radius: radius,
            segmentCount: segmentCount
        )
    }

    @discardableResult
    public func moveBodyVertex(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .moveBodyVertex(
                target: target,
                deltaX: deltaX,
                deltaY: deltaY
            )
        )
    }

    @discardableResult
    public func moveSelectedBodyVertex(
        deltaX: CADExpression,
        deltaY: CADExpression
    ) -> CommandExecutionResult? {
        guard let selectedTarget,
              case .vertex = selectedTarget.component else {
            reportToolStatus("Vertex move requires a vertex selection.", severity: .warning)
            return nil
        }
        return moveBodyVertex(
            target: selectedTarget,
            deltaX: deltaX,
            deltaY: deltaY
        )
    }

    @discardableResult
    public func moveSketchEntityPoint(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        deltaX: CADExpression,
        deltaY: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .moveSketchEntityPoint(
                target: target,
                handle: handle,
                deltaX: deltaX,
                deltaY: deltaY
            )
        )
    }

    @discardableResult
    public func moveSketchSplineControlPoint(
        target: SelectionTarget,
        controlPointIndex: Int,
        deltaX: CADExpression,
        deltaY: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: controlPointIndex,
                deltaX: deltaX,
                deltaY: deltaY
            )
        )
    }

    @discardableResult
    public func slideSketchSplineControlPoints(
        target: SelectionTarget,
        controlPointIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        distance: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .slideSketchSplineControlPoints(
                target: target,
                controlPointIndexes: controlPointIndexes,
                direction: direction,
                distance: distance
            )
        )
    }

    @discardableResult
    public func insertSketchSplineControlPoint(
        target: SelectionTarget,
        fraction: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .insertSketchSplineControlPoint(
                target: target,
                fraction: fraction
            )
        )
    }

    @discardableResult
    public func setSketchCircleParameters(
        target: SelectionTarget,
        center: SketchPoint?,
        radius: CADExpression?
    ) -> CommandExecutionResult? {
        perform(
            .setSketchCircleParameters(
                target: target,
                center: center,
                radius: radius
            )
        )
    }

    @discardableResult
    public func setSketchArcParameters(
        target: SelectionTarget,
        center: SketchPoint?,
        radius: CADExpression?,
        startAngle: CADExpression?,
        endAngle: CADExpression?
    ) -> CommandExecutionResult? {
        perform(
            .setSketchArcParameters(
                target: target,
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle
            )
        )
    }

    @discardableResult
    public func setSketchEntityDimension(
        target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        value: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .setSketchEntityDimension(
                target: target,
                kind: kind,
                value: value
            )
        )
    }

    @discardableResult
    public func convertSketchLineToArc(
        target: SelectionTarget,
        sagitta: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .convertSketchLineToArc(
                target: target,
                sagitta: sagitta
            )
        )
    }

    @discardableResult
    public func convertSketchLineToSpline(
        target: SelectionTarget
    ) -> CommandExecutionResult? {
        perform(
            .convertSketchLineToSpline(target: target)
        )
    }

    @discardableResult
    public func reverseSketchCurve(
        target: SelectionTarget
    ) -> CommandExecutionResult? {
        perform(
            .reverseSketchCurve(target: target)
        )
    }

    @discardableResult
    public func rebuildSketchCurve(
        target: SelectionTarget,
        options: CurveRebuildOptions
    ) -> CommandExecutionResult? {
        perform(
            .rebuildSketchCurve(
                target: target,
                options: options
            )
        )
    }

    @discardableResult
    public func extendSketchCurve(
        target: SelectionTarget,
        distance: CADExpression,
        shape: ExtendCurveShape = .natural
    ) -> CommandExecutionResult? {
        perform(
            .extendSketchCurve(
                target: target,
                distance: distance,
                shape: shape
            )
        )
    }

    @discardableResult
    public func applySketchCornerTreatment(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget? = nil,
        distance: CADExpression,
        treatment: SketchCornerTreatment
    ) -> CommandExecutionResult? {
        perform(
            .applySketchCornerTreatment(
                target: target,
                adjacentTarget: adjacentTarget,
                distance: distance,
                treatment: treatment
            )
        )
    }

    @discardableResult
    public func splitSketchCurve(
        target: SelectionTarget,
        fraction: CADExpression
    ) -> CommandExecutionResult? {
        perform(
            .splitSketchCurve(
                target: target,
                fraction: fraction
            )
        )
    }

    @discardableResult
    public func trimSketchCurveSegment(
        target: SelectionTarget
    ) -> CommandExecutionResult? {
        perform(
            .trimSketchCurveSegment(target: target)
        )
    }

    @discardableResult
    public func cutSketchCurve(
        target: SelectionTarget,
        cutter: SelectionTarget,
        options: CutCurveOptions = CutCurveOptions()
    ) -> CommandExecutionResult? {
        perform(
            .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: options
            )
        )
    }

    @discardableResult
    public func selectSceneNode(_ id: SceneNodeID?) -> Bool {
        do {
            try selection.selectSceneNode(id, in: document)
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    public func selectSceneNodes(_ ids: [SceneNodeID]) -> Bool {
        do {
            try selection.selectSceneNodes(ids, in: document)
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    public func selectTarget(_ target: SelectionTarget?) -> Bool {
        do {
            try selection.selectTarget(target, in: document)
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    public func selectTargets(_ targets: [SelectionTarget]) -> Bool {
        do {
            try selection.selectTargets(targets, in: document)
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    public func clearSelection() {
        selection.clearSelection()
    }

    @discardableResult
    public func hoverSceneNode(_ id: SceneNodeID?) -> Bool {
        do {
            try selection.hoverSceneNode(id, in: document)
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    public func hoverTarget(_ target: SelectionTarget?) -> Bool {
        do {
            try selection.hoverTarget(target, in: document)
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    public func selectNewestSceneNode() -> SceneNodeID? {
        let metadata = document.productMetadata
        var newestID: SceneNodeID?

        func visit(_ id: SceneNodeID) {
            newestID = id
            guard let node = metadata.sceneNodes[id] else {
                return
            }
            for childID in node.childIDs {
                visit(childID)
            }
        }

        for rootID in metadata.rootSceneNodeIDs {
            visit(rootID)
        }

        _ = selectSceneNode(newestID)
        return newestID
    }

    @discardableResult
    public func createDefaultExtrudedCircle() -> CommandExecutionResult? {
        perform(
            .createExtrudedCircle(
                name: nextFeatureName(prefix: "Cylinder"),
                plane: activeSketchPlane(),
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(12.0, .millimeter),
                depth: .length(20.0, .millimeter),
                direction: .normal
            )
        )
    }

    @discardableResult
    public func createDefaultSectionPlane() -> CommandExecutionResult? {
        perform(
            .createSectionPlane(
                name: nextSceneNodeName(prefix: "Section Plane")
            )
        )
    }

    public func reportMeasurementSummary() {
        do {
            let result = try MeasurementService().measure(
                document: document,
                selection: selection
            )
            reportToolStatus(result.message)
        } catch {
            record(error)
        }
    }

    public func reportMeshSummary() {
        do {
            let result = try MeshSummaryService().summarize(
                document: document,
                objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation,
                currentGeneration: generation
            )
            reportToolStatus(result.message)
        } catch {
            record(error)
        }
    }

    public func reportToolStatus(
        _ message: String,
        severity: EditorDiagnostic.Severity = .info
    ) {
        let snapshot = store.snapshot()
        store.restore(
            DocumentSnapshot(
                document: snapshot.document,
                generation: snapshot.generation,
                isDirty: snapshot.isDirty,
                diagnostics: snapshot.diagnostics + [
                    EditorDiagnostic(
                        severity: severity,
                        message: message
                    ),
                ],
                evaluationStatus: snapshot.evaluationStatus,
                evaluatedGeneration: snapshot.evaluatedGeneration,
                renderInvalidation: snapshot.renderInvalidation,
                evaluatedBodyCount: snapshot.evaluatedBodyCount
            )
        )
    }

    public func validateDocument() {
        do {
            try execute(.validateDocument)
        } catch {
            record(error)
        }
    }

    @discardableResult
    public func undo() throws -> CommandExecutionResult {
        let result = try commandStack.undo(in: store)
        selection.pruneMissingReferences(in: document)
        return result
    }

    @discardableResult
    public func redo() throws -> CommandExecutionResult {
        let result = try commandStack.redo(in: store)
        selection.pruneMissingReferences(in: document)
        return result
    }

    private func record(_ error: Error) {
        let snapshot = store.snapshot()
        store.restore(
            DocumentSnapshot(
                document: snapshot.document,
                generation: snapshot.generation,
                isDirty: snapshot.isDirty,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .error,
                        message: error.localizedDescription
                    ),
                ],
                evaluationStatus: .failed(message: error.localizedDescription),
                evaluatedGeneration: snapshot.evaluatedGeneration,
                renderInvalidation: snapshot.renderInvalidation,
                evaluatedBodyCount: snapshot.evaluatedBodyCount
            )
        )
    }

    private func nextFeatureName(prefix: String) -> String {
        let names = Set(
            document.cadDocument.designGraph.nodes.values.compactMap(\.name)
        )
        if !names.contains(prefix) {
            return prefix
        }

        var index = 2
        while names.contains("\(prefix) \(index)") {
            index += 1
        }
        return "\(prefix) \(index)"
    }

    private func sketchPoint2D(
        from modelPoint: Point2D,
        on plane: SketchPlane
    ) -> Point2D {
        let localPoint: Point2D
        switch plane {
        case .xy, .yz, .plane:
            localPoint = modelPoint
        case .zx:
            localPoint = Point2D(
                x: modelPoint.y,
                y: modelPoint.x
            )
        }
        return CADInputValueNormalizer.standard.point(localPoint)
    }

    private func sketchPoint(x: Double, y: Double) -> SketchPoint {
        SketchPoint(
            x: lengthExpressionMeters(x),
            y: lengthExpressionMeters(y)
        )
    }

    private func sketchPoint(_ point: Point2D) -> SketchPoint {
        sketchPoint(x: point.x, y: point.y)
    }

    private func normalizedLengthMeters(_ value: Double) -> Double {
        CADInputValueNormalizer.standard.lengthMeters(value)
    }

    private func normalizedAngleRadians(_ value: Double) -> Double {
        CADInputValueNormalizer.standard.angleRadians(value)
    }

    private func lengthExpressionMeters(_ value: Double) -> CADExpression {
        .length(normalizedLengthMeters(value), .meter)
    }

    private func angleExpressionRadians(_ value: Double) -> CADExpression {
        .angle(normalizedAngleRadians(value), .radian)
    }

    private func nextSceneNodeName(prefix: String) -> String {
        let names = Set(
            document.productMetadata.sceneNodes.values.map(\.name)
        )
        if !names.contains(prefix) {
            return prefix
        }

        var index = 2
        while names.contains("\(prefix) \(index)") {
            index += 1
        }
        return "\(prefix) \(index)"
    }
}
