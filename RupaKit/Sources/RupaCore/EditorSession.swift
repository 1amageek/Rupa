import Foundation
import Observation
import SwiftCAD

@Observable
public final class EditorSession {
    public private(set) var store: CADDocumentStore
    public private(set) var commandStack: CommandStack
    public private(set) var selection: SelectionModel
    public var selectedTool: ModelingTool

    public var document: RupaDocument {
        store.document
    }

    public var generation: DocumentGeneration {
        store.generation
    }

    public var isDirty: Bool {
        store.isDirty
    }

    public var diagnostics: [RupaDiagnostic] {
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

    public var evaluationSnapshot: EvaluationSnapshot {
        store.evaluationSnapshot
    }

    public var selectedSceneNodeID: RupaSceneNodeID? {
        selection.primarySceneNodeID
    }

    public var selectedSceneNode: RupaSceneNode? {
        guard let selectedSceneNodeID else {
            return nil
        }
        return document.productMetadata.sceneNodes[selectedSceneNodeID]
    }

    public init(
        document: RupaDocument = .empty(),
        selectedTool: ModelingTool = .select,
        selection: SelectionModel = .empty,
        diagnostics: [RupaDiagnostic] = []
    ) {
        self.store = CADDocumentStore(
            document: document,
            diagnostics: diagnostics
        )
        self.commandStack = CommandStack()
        self.selectedTool = selectedTool
        var initialSelection = selection
        initialSelection.pruneMissingReferences(in: document)
        self.selection = initialSelection
    }

    public func selectTool(_ tool: ModelingTool) {
        selectedTool = tool
    }

    @discardableResult
    public func activateSelectedToolFromCanvas(
        targetSceneNodeID: RupaSceneNodeID?,
        modelPoint: Point2D? = nil,
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
        sketchPlane: SketchPlane = .xy
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
        let result = try commandStack.execute(
            command,
            in: store,
            expectedGeneration: expectedGeneration
        )
        selection.pruneMissingReferences(in: document)
        return result
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

    public func replaceProductMetadata(_ metadata: RupaProductMetadata) {
        do {
            try execute(.replaceProductMetadata(metadata))
        } catch {
            record(error)
        }
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
    public func createComponentDefinition(
        name: String,
        rootSceneNodeIDs: [RupaSceneNodeID] = []
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
        definitionID: RupaComponentDefinitionID,
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
        _ id: RupaSceneNodeID,
        isVisible: Bool
    ) {
        perform(.setSceneNodeVisibility(id: id, isVisible: isVisible))
    }

    public func setSceneNodeLock(
        _ id: RupaSceneNodeID,
        isLocked: Bool
    ) {
        perform(.setSceneNodeLock(id: id, isLocked: isLocked))
    }

    public func setSceneNodeTransform(
        _ id: RupaSceneNodeID,
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
        _ id: RupaSceneNodeID,
        materialID: MaterialID?
    ) {
        perform(
            .setSceneNodeMaterial(
                id: id,
                materialID: materialID
            )
        )
    }

    public func setComponentInstanceVisibility(
        _ id: RupaComponentInstanceID,
        isVisible: Bool
    ) {
        perform(.setComponentInstanceVisibility(id: id, isVisible: isVisible))
    }

    public func setComponentInstanceLock(
        _ id: RupaComponentInstanceID,
        isLocked: Bool
    ) {
        perform(.setComponentInstanceLock(id: id, isLocked: isLocked))
    }

    public func setComponentInstanceTransform(
        _ id: RupaComponentInstanceID,
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
    public func createDefaultRectangleSketch() -> CommandExecutionResult? {
        perform(
            .createRectangleSketch(
                name: nextFeatureName(prefix: "Rectangle Sketch"),
                plane: .xy,
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

        let halfSideMeters = LengthDisplayUnit.millimeter.meters(from: 20.0)
        let center = sketchPoint2D(from: centerModelPoint, on: sketchPlane)
        return perform(
            .createRectangleSketchFromCorners(
                name: nextFeatureName(prefix: "Rectangle Sketch"),
                plane: sketchPlane,
                firstCorner: SketchPoint(
                    x: .length(center.x - halfSideMeters, .meter),
                    y: .length(center.y - halfSideMeters, .meter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(center.x + halfSideMeters, .meter),
                    y: .length(center.y + halfSideMeters, .meter)
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
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
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
                    x: .length(minX, .meter),
                    y: .length(minY, .meter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(maxX, .meter),
                    y: .length(maxY, .meter)
                )
            )
        )
    }

    @discardableResult
    public func createDefaultCircleSketch() -> CommandExecutionResult? {
        perform(
            .createCircleSketch(
                name: nextFeatureName(prefix: "Circle Sketch"),
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(12.0, .millimeter)
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
        return perform(
            .createCircleSketch(
                name: nextFeatureName(prefix: "Circle Sketch"),
                plane: sketchPlane,
                center: SketchPoint(
                    x: .length(center.x, .meter),
                    y: .length(center.y, .meter)
                ),
                radius: .length(12.0, .millimeter)
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
        let radius = sqrt(deltaX * deltaX + deltaY * deltaY)
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
    public func createDefaultExtrudedRectangle() -> CommandExecutionResult? {
        perform(
            .createExtrudedRectangle(
                name: nextFeatureName(prefix: "Box"),
                plane: .xy,
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
                    x: .length(center.x - halfSideMeters, .meter),
                    y: .length(center.y - halfSideMeters, .meter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(center.x + halfSideMeters, .meter),
                    y: .length(center.y + halfSideMeters, .meter)
                ),
                depth: .length(sideMeters, .meter),
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
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
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
                    x: .length(minX, .meter),
                    y: .length(minY, .meter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(maxX, .meter),
                    y: .length(maxY, .meter)
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
    public func createDefaultSolid(fromSceneNode sceneNodeID: RupaSceneNodeID?) -> CommandExecutionResult? {
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

    @discardableResult
    public func selectSceneNode(_ id: RupaSceneNodeID?) -> Bool {
        do {
            try selection.selectSceneNode(id, in: document)
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    public func selectSceneNodes(_ ids: [RupaSceneNodeID]) -> Bool {
        do {
            try selection.selectSceneNodes(ids, in: document)
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
    public func hoverSceneNode(_ id: RupaSceneNodeID?) -> Bool {
        do {
            try selection.hoverSceneNode(id, in: document)
            return true
        } catch {
            reportToolStatus(error.localizedDescription, severity: .warning)
            return false
        }
    }

    @discardableResult
    public func selectNewestSceneNode() -> RupaSceneNodeID? {
        let metadata = document.productMetadata
        var newestID: RupaSceneNodeID?

        func visit(_ id: RupaSceneNodeID) {
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
                plane: .xy,
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
            let result = try RupaMeasurementService().measure(
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
            let result = try RupaMeshSummaryService().summarize(document: document)
            reportToolStatus(result.message)
        } catch {
            record(error)
        }
    }

    public func reportToolStatus(
        _ message: String,
        severity: RupaDiagnostic.Severity = .info
    ) {
        let snapshot = store.snapshot()
        store.restore(
            DocumentSnapshot(
                document: snapshot.document,
                generation: snapshot.generation,
                isDirty: snapshot.isDirty,
                diagnostics: snapshot.diagnostics + [
                    RupaDiagnostic(
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
                    RupaDiagnostic(
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
        switch plane {
        case .xy, .yz, .plane:
            return modelPoint
        case .zx:
            return Point2D(
                x: modelPoint.y,
                y: modelPoint.x
            )
        }
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
