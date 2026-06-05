import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func commandStackUpdatesGenerationAndDirtyState() async throws {
    let session = EditorSession()

    let result = try session.execute(
        .setDisplayUnit(.meter),
        expectedGeneration: DocumentGeneration(0)
    )

    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.isDirty)
    #expect(session.document.displayUnit == .meter)
    #expect(session.commandStack.canUndo)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedGeneration == DocumentGeneration(1))
    #expect(session.evaluatedBodyCount == 0)
    #expect(session.renderInvalidation == RenderInvalidation(
        generation: DocumentGeneration(1),
        reason: .evaluated
    ))
}

@MainActor
@Test func commandStackRejectsStaleGenerationBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(.setDisplayUnit(.meter))

    var caught: EditorError?
    do {
        _ = try session.execute(
            .renameDocument(name: "Stale"),
            expectedGeneration: DocumentGeneration(0)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .documentGenerationMismatch)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Untitled")
    #expect(session.evaluatedGeneration == DocumentGeneration(1))
}

@MainActor
@Test func commandStackSupportsUndoAndRedo() async throws {
    let session = EditorSession()

    _ = try session.execute(.setDisplayUnit(.meter))
    #expect(session.document.displayUnit == .meter)

    _ = try session.undo()
    #expect(session.document.displayUnit == .millimeter)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluatedGeneration == DocumentGeneration(2))
    #expect(session.renderInvalidation.generation == DocumentGeneration(2))
    #expect(!session.commandStack.canUndo)
    #expect(session.commandStack.canRedo)

    _ = try session.redo()
    #expect(session.document.displayUnit == .meter)
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.evaluatedGeneration == DocumentGeneration(3))
    #expect(session.renderInvalidation.generation == DocumentGeneration(3))
    #expect(session.commandStack.canUndo)
    #expect(!session.commandStack.canRedo)
}

@MainActor
@Test func validationCommandDoesNotCreateUndoEntry() async throws {
    let session = EditorSession()

    let result = try session.execute(.validateDocument)

    #expect(!result.didMutate)
    #expect(result.generation == DocumentGeneration(0))
    #expect(!session.commandStack.canUndo)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedGeneration == DocumentGeneration(0))
    #expect(session.renderInvalidation == RenderInvalidation(
        generation: DocumentGeneration(0),
        reason: .evaluated
    ))
}

@MainActor
@Test func productMetadataCommandParticipatesInUndoRedo() async throws {
    let session = EditorSession()
    let initialMetadata = session.document.productMetadata
    var metadata = ProductMetadata.empty()
    let rootID = try #require(metadata.rootSceneNodeIDs.first)
    metadata.sceneNodes[rootID]?.name = "Universal Product Scene"

    let result = try session.execute(
        .replaceProductMetadata(metadata),
        expectedGeneration: DocumentGeneration(0)
    )

    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.productMetadata == metadata)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedGeneration == DocumentGeneration(1))

    _ = try session.undo()
    #expect(session.document.productMetadata == initialMetadata)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluatedGeneration == DocumentGeneration(2))

    _ = try session.redo()
    #expect(session.document.productMetadata == metadata)
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.evaluatedGeneration == DocumentGeneration(3))
}

@MainActor
@Test func editorSessionReplaceProductMetadataUsesCommandPath() async throws {
    let session = EditorSession()
    let initialMetadata = session.document.productMetadata
    var metadata = initialMetadata
    let rootID = try #require(metadata.rootSceneNodeIDs.first)
    metadata.sceneNodes[rootID]?.isVisible = false
    metadata.sceneNodes[rootID]?.isLocked = true

    session.replaceProductMetadata(metadata)

    #expect(session.document.productMetadata == metadata)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.isDirty)
    #expect(session.commandStack.canUndo)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedGeneration == DocumentGeneration(1))

    _ = try session.undo()
    #expect(session.document.productMetadata == initialMetadata)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func editorSessionCreateDefaultRectangleSketchUsesCommandPath() async throws {
    let session = EditorSession()

    let result = try #require(session.createDefaultRectangleSketch())

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "createRectangleSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(feature.name == "Rectangle Sketch")
    #expect(sketch.entities.count == 4)
    #expect(session.commandStack.canUndo)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionCreateDefaultExtrudedRectangleUsesCommandPath() async throws {
    let session = EditorSession()

    let result = try #require(session.createDefaultExtrudedRectangle())

    let order = session.document.cadDocument.designGraph.order
    let sketchFeatureID = try #require(order.first)
    let bodyFeatureID = try #require(order.last)
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "createExtrudedRectangle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(order.count == 2)
    #expect(extrude.profile.featureID == sketchFeatureID)
    #expect(bodyFeature.name == "Box")
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionCreateDefaultCircleSketchUsesCommandPath() async throws {
    let session = EditorSession()

    let result = try #require(session.createDefaultCircleSketch())

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let entity = try #require(sketch.entities.values.first)
    guard case .circle = entity else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "createCircleSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(feature.name == "Circle Sketch")
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionReportToolStatusDoesNotMutateDocument() async throws {
    let session = EditorSession()

    session.reportToolStatus("Tool status message.")

    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
    #expect(session.diagnostics.count == 1)
    #expect(session.diagnostics.first?.severity == .info)
}

@MainActor
@Test func editorSessionSelectionDoesNotMutateDocument() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultCircleSketch())
    let generation = session.generation
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let sketchNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(sketchFeatureID)
    }?.key)

    let didSelect = session.selectSceneNode(sketchNodeID)

    #expect(didSelect)
    #expect(session.selectedSceneNodeID == sketchNodeID)
    #expect(session.selectedSceneNode?.reference == .sketch(sketchFeatureID))
    #expect(session.selection.selectedSceneNodeReferences(in: session.document) == [.sketch(sketchFeatureID)])
    #expect(session.generation == generation)
    #expect(session.isDirty)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func editorSessionSelectionRejectsMissingSceneNodeWithoutEvaluationFailure() async throws {
    let session = EditorSession()

    let didSelect = session.selectSceneNode(SceneNodeID())

    #expect(!didSelect)
    #expect(session.selectedSceneNodeID == nil)
    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
    #expect(session.evaluationStatus == .notEvaluated)
    #expect(session.diagnostics.first?.severity == .warning)
}

@MainActor
@Test func editorSessionHoverDoesNotMutateDocument() async throws {
    let session = EditorSession()
    let rootSceneNodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)

    let didHover = session.hoverSceneNode(rootSceneNodeID)

    #expect(didHover)
    #expect(session.selection.hoveredSceneNodeID == rootSceneNodeID)
    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
    #expect(session.diagnostics.isEmpty)

    let didClear = session.hoverSceneNode(nil)

    #expect(didClear)
    #expect(session.selection.hoveredSceneNodeID == nil)
    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
    #expect(session.diagnostics.isEmpty)
}

@MainActor
@Test func editorSessionPrunesSelectionWhenSelectedNodeIsRemovedByReset() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultCircleSketch())
    let selectedID = try #require(session.selectNewestSceneNode())
    #expect(session.selectedSceneNodeID == selectedID)

    session.resetDocument()

    #expect(session.selectedSceneNodeID == nil)
    #expect(session.selection.selectedSceneNodeIDs.isEmpty)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func editorSessionMeasurementSummaryDoesNotMutateDocument() async throws {
    let session = EditorSession()

    session.reportMeasurementSummary()

    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
    #expect(session.diagnostics.first?.message.contains("Measurement summary") == true)
}

@MainActor
@Test func editorSessionSelectedMeasurementDoesNotMutateDocument() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let generation = session.generation
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let sketchNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(sketchFeatureID)
    }?.key)
    #expect(session.selectSceneNode(sketchNodeID))

    session.reportMeasurementSummary()

    #expect(session.generation == generation)
    #expect(session.isDirty)
    #expect(session.commandStack.canUndo)
    #expect(session.diagnostics.last?.message.contains("Selection measurement") == true)
}

@MainActor
@Test func measurementServiceMeasuresExtrudedRectangleBoundsAreaAndVolume() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let result = try MeasurementService().measure(document: session.document)
    let bounds = try #require(result.bounds)

    #expect(result.counts.sourceFeatures == 2)
    #expect(result.counts.sketches == 1)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 1)
    #expect(abs(result.totals.profileAreaSquareMeters - 0.0008) < 0.000_000_000_001)
    #expect(abs(result.totals.solidVolumeCubicMeters - 0.000008) < 0.000_000_000_001)
    #expect(abs(bounds.sizeX - 0.04) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ - 0.01) < 0.000_000_000_001)
}

@MainActor
@Test func measurementServiceMeasuresSelectedSketchOnly() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let sketchNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(sketchFeatureID)
    }?.key)
    #expect(session.selectSceneNode(sketchNodeID))

    let result = try MeasurementService().measure(
        document: session.document,
        selection: session.selection
    )
    let bounds = try #require(result.bounds)

    #expect(result.scope == .selection)
    #expect(result.counts.sourceFeatures == 1)
    #expect(result.counts.sketches == 1)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 0)
    #expect(abs(result.totals.profileAreaSquareMeters - 0.0008) < 0.000_000_000_001)
    #expect(result.totals.solidVolumeCubicMeters == 0.0)
    #expect(abs(bounds.sizeX - 0.04) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ) < 0.000_000_000_001)
    #expect(result.message.contains("Selection measurement"))
}

@MainActor
@Test func measurementServiceMeasuresSelectedSolidWithSourceProfile() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    #expect(session.selectSceneNode(bodyNodeID))

    let result = try MeasurementService().measure(
        document: session.document,
        selection: session.selection
    )
    let bounds = try #require(result.bounds)

    #expect(result.scope == .selection)
    #expect(result.counts.sourceFeatures == 2)
    #expect(result.counts.sketches == 1)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 1)
    #expect(abs(result.totals.profileAreaSquareMeters - 0.0008) < 0.000_000_000_001)
    #expect(abs(result.totals.solidVolumeCubicMeters - 0.000008) < 0.000_000_000_001)
    #expect(abs(bounds.sizeX - 0.04) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ - 0.01) < 0.000_000_000_001)
}

@MainActor
@Test func measurementServiceMeasuresExtrudedCircleAreaAndVolume() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedCircle(
            name: "Measured Cylinder",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(10.0, .millimeter),
            depth: .length(20.0, .millimeter),
            direction: .normal
        )
    )

    let result = try MeasurementService().measure(document: session.document)
    let bounds = try #require(result.bounds)

    #expect(result.profiles.first?.kind == .circle)
    #expect(result.counts.solids == 1)
    #expect(abs(result.totals.profileAreaSquareMeters - Double.pi * 0.0001) < 0.000_000_000_001)
    #expect(abs(result.totals.solidVolumeCubicMeters - Double.pi * 0.000002) < 0.000_000_000_001)
    #expect(abs(bounds.sizeX - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ - 0.02) < 0.000_000_000_001)
}

@MainActor
@Test func measurementServiceKeepsOpenLineSketchOutOfAreaAndVolumeTotals() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Open Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )

    let result = try MeasurementService().measure(document: session.document)
    let bounds = try #require(result.bounds)

    #expect(result.counts.sourceFeatures == 1)
    #expect(result.counts.sketches == 1)
    #expect(result.counts.profiles == 0)
    #expect(result.counts.solids == 0)
    #expect(result.totals.profileAreaSquareMeters == 0.0)
    #expect(result.totals.solidVolumeCubicMeters == 0.0)
    #expect(abs(bounds.sizeX - 0.01) < 0.000_000_000_001)
}

@MainActor
@Test func editorSessionMeshSummaryDoesNotMutateDocument() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let generation = session.generation

    session.reportMeshSummary()

    #expect(session.generation == generation)
    #expect(session.isDirty)
    #expect(session.commandStack.canUndo)
    #expect(session.diagnostics.last?.message.contains("Mesh summary") == true)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func meshSummaryServiceReportsEvaluatedMeshCountsAndBounds() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let result = try MeshSummaryService().summarize(document: session.document)
    let bounds = try #require(result.bounds)
    let body = try #require(result.bodies.first)

    #expect(result.bodyCount == 1)
    #expect(result.vertexCount > 0)
    #expect(result.triangleCount > 0)
    #expect(result.indexedElementCount == result.triangleCount * 3)
    #expect(body.vertexCount == result.vertexCount)
    #expect(body.triangleCount == result.triangleCount)
    #expect(abs(bounds.sizeX - 0.04) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ - 0.01) < 0.000_000_000_001)
}

@MainActor
@Test func meshSummaryServiceReportsEmptySketchOnlyDocumentWithoutEvaluationFailure() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultCircleSketch())

    let result = try MeshSummaryService().summarize(document: session.document)

    #expect(result.bodyCount == 0)
    #expect(result.vertexCount == 0)
    #expect(result.triangleCount == 0)
    #expect(result.bounds == nil)
    #expect(result.diagnostics.first?.message.contains("No generated body meshes") == true)
}

@MainActor
@Test func editorSessionCreateDefaultSolidUsesSelectedSketchWhenAvailable() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultCircleSketch())
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let sketchNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(sketchFeatureID)
    }?.key)
    #expect(session.selectSceneNode(sketchNodeID))

    let result = try #require(session.createDefaultSolid())

    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "extrudeProfile")
    #expect(result.generation == DocumentGeneration(2))
    #expect(extrude.profile.featureID == sketchFeatureID)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func editorSessionPrunesSelectionWhenUndoRemovesSelectedNode() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultCircleSketch())
    let selectedID = try #require(session.selectNewestSceneNode())
    #expect(session.selectedSceneNodeID == selectedID)

    _ = try session.undo()

    #expect(session.selectedSceneNodeID == nil)
    #expect(session.selection.selectedSceneNodeIDs.isEmpty)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func editorSessionCreateDefaultSectionPlaneUsesMetadataCommandPath() async throws {
    let session = EditorSession()

    let result = try #require(session.createDefaultSectionPlane())

    #expect(result.commandName == "createSectionPlane")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
    #expect(session.document.productMetadata.sceneNodes.values.contains { node in
        node.name == "Section Plane" && node.reference == .construction
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionActivatesEveryCanvasToolbarTool() async throws {
    let session = EditorSession()

    for tool in ModelingTool.allCases {
        let result = session.activateTool(tool)
        #expect(result.tool == tool)
        #expect(!result.didMutate)
        #expect(result.commandName == nil)
        #expect(!result.revealsDiagnostics)
        #expect(session.selectedTool == tool)
        #expect(session.generation == DocumentGeneration(0))
        #expect(session.document.cadDocument.designGraph.order.isEmpty)
        #expect(!session.isDirty)
        #expect(!session.commandStack.canUndo)
    }
}

@MainActor
@Test func editorSessionActivatesSelectedCanvasToolFromCanvasTarget() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultRectangleSketch())
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let sketchNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(sketchFeatureID)
    }?.key)

    session.selectTool(.select)
    let selectResult = session.activateSelectedToolFromCanvas(targetSceneNodeID: sketchNodeID)
    #expect(selectResult.tool == .select)
    #expect(!selectResult.didMutate)
    #expect(session.selectedSceneNodeID == sketchNodeID)

    let clearResult = session.activateSelectedToolFromCanvas(targetSceneNodeID: nil)
    #expect(clearResult.tool == .select)
    #expect(!clearResult.didMutate)
    #expect(session.selectedSceneNodeID == nil)

    session.selectTool(.solid)
    let solidResult = session.activateSelectedToolFromCanvas(targetSceneNodeID: sketchNodeID)
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    guard case let .extrude(extrude) = bodyFeature.operation else {
        #expect(Bool(false))
        return
    }

    #expect(solidResult.commandName == "extrudeProfile")
    #expect(solidResult.didMutate)
    #expect(solidResult.selectedSceneNodeID == bodyNodeID)
    #expect(extrude.profile.featureID == sketchFeatureID)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.selectedTool == .select)

    let generation = session.generation
    session.selectTool(.solid)
    let rejectedResult = session.activateSelectedToolFromCanvas(targetSceneNodeID: bodyNodeID)
    #expect(!rejectedResult.didMutate)
    #expect(rejectedResult.revealsDiagnostics)
    #expect(session.generation == generation)
    #expect(session.diagnostics.last?.message == "Solid tool requires a sketch profile canvas target.")
}

@MainActor
@Test func editorSessionActivatesSketchToolFromCanvasBackground() async throws {
    let session = EditorSession()

    session.selectTool(.sketch)
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.0, y: 0.0)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas click should create a sketch feature.")
        return
    }
    let points = try resolvedLinePoints(
        in: sketch,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createRectangleSketchFromCorners")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(points == Set([
        Point2D(x: -0.02, y: -0.02),
        Point2D(x: 0.02, y: -0.02),
        Point2D(x: 0.02, y: 0.02),
        Point2D(x: -0.02, y: 0.02),
    ]))
}

@MainActor
@Test func editorSessionActivatesSurfaceToolFromCanvasBackground() async throws {
    let session = EditorSession()

    session.selectTool(.surface)
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: -0.04, y: 0.025)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas click should create a circle sketch feature.")
        return
    }
    let circle = try #require(resolvedCircle(in: sketch))
    let center = try resolvedPoint(
        circle.center,
        parameters: session.document.cadDocument.parameters
    )
    let radius = try resolvedLength(
        circle.radius,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createCircleSketch")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    #expect(center == Point2D(x: -0.04, y: 0.025))
    #expect(abs(radius - 0.012) < 0.000_000_000_001)
}

@MainActor
@Test func editorSessionActivatesSolidToolFromCanvasBackground() async throws {
    let session = EditorSession()

    session.selectTool(.solid)
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.0, y: 0.0)
    )

    let order = session.document.cadDocument.designGraph.order
    let sketchFeatureID = try #require(order.first)
    let bodyFeatureID = try #require(order.last)
    let sketchFeature = try #require(session.document.cadDocument.designGraph.nodes[sketchFeatureID])
    guard case let .sketch(sketch) = sketchFeature.operation else {
        Issue.record("Canvas click should create a source sketch feature.")
        return
    }
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Canvas click should create a body feature.")
        return
    }
    let points = try resolvedLinePoints(
        in: sketch,
        parameters: session.document.cadDocument.parameters
    )
    let distance = try resolvedLength(
        extrude.distance,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .body(bodyFeatureID))
    #expect(session.selectedTool == .select)
    #expect(order.count == 2)
    #expect(points == Set([
        Point2D(x: -0.02, y: -0.02),
        Point2D(x: 0.02, y: -0.02),
        Point2D(x: 0.02, y: 0.02),
        Point2D(x: -0.02, y: 0.02),
    ]))
    #expect(abs(distance - 0.04) < 0.000_000_000_001)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func editorSessionCreatesRectangleSketchFromCanvasDrag() async throws {
    let session = EditorSession()

    session.selectTool(.sketch)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.03, y: 0.04),
        endModelPoint: Point2D(x: -0.01, y: 0.01)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas drag should create a sketch feature.")
        return
    }
    let points = try resolvedLinePoints(
        in: sketch,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createRectangleSketchFromCorners")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    #expect(sketch.entities.count == 4)
    #expect(sketch.constraints.count == 8)
    #expect(points == Set([
        Point2D(x: -0.01, y: 0.01),
        Point2D(x: 0.03, y: 0.01),
        Point2D(x: 0.03, y: 0.04),
        Point2D(x: -0.01, y: 0.04),
    ]))
}

@MainActor
@Test func editorSessionRejectsDegenerateCanvasRectangleDrag() async throws {
    let session = EditorSession()

    session.selectTool(.sketch)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 1.0, y: 1.0),
        endModelPoint: Point2D(x: 1.0, y: 2.0)
    )

    #expect(!result.didMutate)
    #expect(result.revealsDiagnostics)
    #expect(session.selectedTool == .sketch)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.diagnostics.last?.message == "Canvas rectangle drag requires a non-zero width and height.")
}

@MainActor
@Test func editorSessionCreatesCircleSketchFromCanvasDrag() async throws {
    let session = EditorSession()

    session.selectTool(.surface)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.01, y: -0.02),
        endModelPoint: Point2D(x: 0.04, y: 0.02)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas drag should create a sketch feature.")
        return
    }
    let circle = try #require(resolvedCircle(in: sketch))
    let center = try resolvedPoint(
        circle.center,
        parameters: session.document.cadDocument.parameters
    )
    let radius = try resolvedLength(
        circle.radius,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createCircleSketch")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    #expect(sketch.entities.count == 1)
    #expect(center == Point2D(x: 0.01, y: -0.02))
    #expect(abs(radius - 0.05) < 0.000_000_000_001)
}

@MainActor
@Test func editorSessionRejectsDegenerateCanvasCircleDrag() async throws {
    let session = EditorSession()

    session.selectTool(.surface)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 1.0, y: 1.0),
        endModelPoint: Point2D(x: 1.0, y: 1.0)
    )

    #expect(!result.didMutate)
    #expect(result.revealsDiagnostics)
    #expect(session.selectedTool == .surface)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.diagnostics.last?.message == "Canvas circle drag requires a non-zero radius.")
}

@MainActor
@Test func editorSessionCreatesExtrudedRectangleFromCanvasDrag() async throws {
    let session = EditorSession()

    session.selectTool(.solid)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.02, y: -0.01),
        endModelPoint: Point2D(x: 0.05, y: 0.03)
    )

    let order = session.document.cadDocument.designGraph.order
    let sketchFeatureID = try #require(order.first)
    let bodyFeatureID = try #require(order.last)
    let sketchFeature = try #require(session.document.cadDocument.designGraph.nodes[sketchFeatureID])
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .sketch(sketch) = sketchFeature.operation else {
        Issue.record("Canvas solid drag should create a source sketch feature.")
        return
    }
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Canvas solid drag should create a body feature.")
        return
    }
    let points = try resolvedLinePoints(
        in: sketch,
        parameters: session.document.cadDocument.parameters
    )
    let distance = try resolvedLength(
        extrude.distance,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .body(bodyFeatureID))
    #expect(session.selectedTool == .select)
    #expect(order.count == 2)
    #expect(sketch.entities.count == 4)
    #expect(points == Set([
        Point2D(x: 0.02, y: -0.01),
        Point2D(x: 0.05, y: -0.01),
        Point2D(x: 0.05, y: 0.03),
        Point2D(x: 0.02, y: 0.03),
    ]))
    #expect(extrude.profile.featureID == sketchFeatureID)
    #expect(abs(distance - 0.01) < 0.000_000_000_001)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func editorSessionRejectsDegenerateCanvasSolidDrag() async throws {
    let session = EditorSession()

    session.selectTool(.solid)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 1.0, y: 1.0),
        endModelPoint: Point2D(x: 1.0, y: 2.0)
    )

    #expect(!result.didMutate)
    #expect(result.revealsDiagnostics)
    #expect(session.selectedTool == .solid)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.diagnostics.last?.message == "Canvas solid drag requires a non-zero width and height.")
}

@MainActor
@Test func rectangleSketchFromCornersCommandRejectsDegenerateCornersBeforeMutation() async throws {
    let session = EditorSession()
    var error: EditorError?

    do {
        _ = try session.execute(
            .createRectangleSketchFromCorners(
                name: "Invalid Rectangle",
                plane: .xy,
                firstCorner: SketchPoint(
                    x: .length(1.0, .meter),
                    y: .length(1.0, .meter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(1.0, .meter),
                    y: .length(2.0, .meter)
                )
            )
        )
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .commandInvalid)
    #expect(error?.message == "Rectangle sketch corners must define a non-zero width and height.")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
}

@MainActor
@Test func extrudedRectangleFromCornersCommandRejectsDegenerateCornersBeforeMutation() async throws {
    let session = EditorSession()
    var error: EditorError?

    do {
        _ = try session.execute(
            .createExtrudedRectangleFromCorners(
                name: "Invalid Box",
                plane: .xy,
                firstCorner: SketchPoint(
                    x: .length(1.0, .meter),
                    y: .length(1.0, .meter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(1.0, .meter),
                    y: .length(2.0, .meter)
                ),
                depth: .length(10.0, .millimeter),
                direction: .normal
            )
        )
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .commandInvalid)
    #expect(error?.message == "Rectangle sketch corners must define a non-zero width and height.")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
}

@MainActor
@Test func addSketchConstraintCommandMutatesExistingSketchThroughCommandPath() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Constraint Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(12.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(singleSketchEntityID(in: session.document, featureID: featureID))

    let result = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(lineID)
        )
    )

    let sketch = try #require(sketchFeature(in: session.document, featureID: featureID))
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(sketch.constraints == [.horizontal(lineID)])
    #expect(session.evaluationStatus == .valid)
    #expect(session.commandStack.canUndo)

    _ = try session.undo()
    let restoredSketch = try #require(sketchFeature(in: session.document, featureID: featureID))
    #expect(restoredSketch.constraints.isEmpty)
    #expect(session.generation == DocumentGeneration(3))
}

@MainActor
@Test func addSketchConstraintCommandRejectsDuplicateConstraintBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Duplicate Constraint Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(12.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(singleSketchEntityID(in: session.document, featureID: featureID))
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(lineID)
        )
    )

    var error: EditorError?
    do {
        _ = try session.execute(
            .addSketchConstraint(
                featureID: featureID,
                constraint: .horizontal(lineID)
            )
        )
    } catch let caught as EditorError {
        error = caught
    }

    let sketch = try #require(sketchFeature(in: session.document, featureID: featureID))
    #expect(error?.code == .commandInvalid)
    #expect(error?.message == "Sketch constraint already exists.")
    #expect(session.generation == DocumentGeneration(2))
    #expect(sketch.constraints == [.horizontal(lineID)])
}

@MainActor
@Test func addSketchConstraintCommandRejectsInvalidGeometryBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Invalid Constraint Source",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter)
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let circleID = try #require(singleSketchEntityID(in: session.document, featureID: featureID))

    var error: EditorError?
    do {
        _ = try session.execute(
            .addSketchConstraint(
                featureID: featureID,
                constraint: .horizontal(circleID)
            )
        )
    } catch let caught as EditorError {
        error = caught
    }

    let sketch = try #require(sketchFeature(in: session.document, featureID: featureID))
    #expect(error?.code == .referenceUnresolved)
    #expect(error?.message.contains("Sketch reference must point to a line entity.") == true)
    #expect(session.generation == DocumentGeneration(1))
    #expect(sketch.constraints.isEmpty)
}

@MainActor
@Test func circleSketchCommandRejectsNonPositiveRadiusBeforeMutation() async throws {
    let session = EditorSession()
    var error: EditorError?

    do {
        _ = try session.execute(
            .createCircleSketch(
                name: "Invalid Circle",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .meter),
                    y: .length(0.0, .meter)
                ),
                radius: .length(0.0, .meter)
            )
        )
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .commandInvalid)
    #expect(error?.message == "Circle sketch radius must be greater than zero.")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
}

@MainActor
@Test func productMetadataValidationFailurePublishesDiagnostics() async throws {
    let session = EditorSession()
    var metadata = ProductMetadata.empty()
    let rootID = try #require(metadata.rootSceneNodeIDs.first)
    metadata.sceneNodes[rootID]?.reference = .feature(FeatureID())

    let result = try session.execute(.replaceProductMetadata(metadata))

    guard case .failed(let message) = session.evaluationStatus else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(message.contains("existing CAD feature"))
    #expect(session.diagnostics.first?.severity == .error)
    #expect(session.renderInvalidation == RenderInvalidation(
        generation: DocumentGeneration(1),
        reason: .evaluationFailed
    ))
}

@MainActor
@Test func parameterCommandParticipatesInUndoRedo() async throws {
    let session = EditorSession()

    let result = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(12.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )

    let parameter = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    guard case .constant(let quantity) = parameter.expression else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(quantity.kind == .length)
    #expect(abs(quantity.value - 0.012) < 0.000_000_000_001)
    #expect(session.document.cadDocument.parameters.revision.value == 1)
    #expect(session.evaluationStatus == .valid)

    _ = try session.undo()
    #expect(session.document.cadDocument.parameters.parameters.isEmpty)
    #expect(session.generation == DocumentGeneration(2))

    _ = try session.redo()
    #expect(session.document.cadDocument.parameters.parameters.values.contains { $0.name == "width" })
    #expect(session.generation == DocumentGeneration(3))
}

@MainActor
@Test func parameterCommandUpdatesExistingName() async throws {
    let session = EditorSession()

    _ = try session.execute(
        .upsertParameter(
            name: "height",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    _ = try session.execute(
        .upsertParameter(
            name: "height",
            expression: .constant(.length(20.0, unit: .millimeter)),
            kind: .length
        )
    )

    let parameters = session.document.cadDocument.parameters.parameters.values.filter { $0.name == "height" }
    let parameter = try #require(parameters.first)
    guard case .constant(let quantity) = parameter.expression else {
        #expect(Bool(false))
        return
    }
    #expect(parameters.count == 1)
    #expect(abs(quantity.value - 0.02) < 0.000_000_000_001)
    #expect(session.document.cadDocument.parameters.revision.value == 2)
}

@MainActor
@Test func parameterDeleteCommandParticipatesInUndoRedo() async throws {
    let session = EditorSession()

    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(12.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    let result = try session.execute(
        .deleteParameter(name: "width"),
        expectedGeneration: DocumentGeneration(1)
    )

    #expect(result.commandName == "deleteParameter")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.parameters.parameters.isEmpty)
    #expect(session.document.cadDocument.parameters.revision.value == 2)
    #expect(session.evaluationStatus == .valid)

    _ = try session.undo()
    #expect(session.document.cadDocument.parameters.parameters.values.contains { $0.name == "width" })
    #expect(session.generation == DocumentGeneration(3))

    _ = try session.redo()
    #expect(session.document.cadDocument.parameters.parameters.isEmpty)
    #expect(session.generation == DocumentGeneration(4))
}

@MainActor
@Test func parameterDeleteRejectsReferencedParameterBeforeMutation() async throws {
    let session = EditorSession()

    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(12.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    let width = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    _ = try session.execute(
        .upsertParameter(
            name: "height",
            expression: .multiply(
                .reference(width.id),
                .constant(.scalar(2.0))
            ),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(1)
    )

    var caught: EditorError?
    do {
        _ = try session.execute(
            .deleteParameter(name: "width"),
            expectedGeneration: DocumentGeneration(2)
        )
    } catch let error as EditorError {
        caught = error
    }

    let parameterNames = session.document.cadDocument.parameters.parameters.values.map(\.name).sorted()
    #expect(caught?.code == .referenceUnresolved)
    #expect(caught?.localizedDescription.contains("still referenced") == true)
    #expect(parameterNames == ["height", "width"])
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.parameters.revision.value == 2)
}

@MainActor
@Test func parameterKindMismatchPublishesDiagnostics() async throws {
    let session = EditorSession()

    _ = try session.execute(
        .upsertParameter(
            name: "bad",
            expression: .constant(.length(1.0, unit: .meter)),
            kind: .angle
        )
    )

    guard case .failed(let message) = session.evaluationStatus else {
        #expect(Bool(false))
        return
    }
    #expect(message.contains("kindMismatch"))
    #expect(session.diagnostics.first?.severity == .error)
    #expect(session.renderInvalidation == RenderInvalidation(
        generation: DocumentGeneration(1),
        reason: .evaluationFailed
    ))
}

@MainActor
@Test func rectangleSketchCommandCreatesValidSketchSourceWithoutGeneratedBody() async throws {
    let session = EditorSession()

    let result = try session.execute(
        .createRectangleSketch(
            name: "Base Sketch",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(0)
    )

    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[sketchFeatureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let rootSceneNodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)
    let rootSceneNode = try #require(session.document.productMetadata.sceneNodes[rootSceneNodeID])
    let sketchSceneNodeID = try #require(rootSceneNode.childIDs.first)

    #expect(result.didMutate)
    #expect(result.commandName == "createRectangleSketch")
    #expect(result.generation == DocumentGeneration(1))
    #expect(feature.name == "Base Sketch")
    #expect(sketch.entities.count == 4)
    #expect(session.document.cadDocument.designGraph.revision.value == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
    #expect(session.document.productMetadata.sceneNodes[sketchSceneNodeID]?.reference == .sketch(sketchFeatureID))
}

@MainActor
@Test func lineSketchCommandCreatesValidSketchPrimitive() async throws {
    let session = EditorSession()

    let result = try session.execute(
        .createLineSketch(
            name: "Guide Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(12.0, .millimeter),
                y: .length(4.0, .millimeter)
            )
        ),
        expectedGeneration: DocumentGeneration(0)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let line = try #require(sketch.entities.values.first)
    guard case .line = line else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "createLineSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(feature.name == "Guide Line")
    #expect(sketch.entities.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@MainActor
@Test func circleSketchCommandCreatesValidSketchPrimitive() async throws {
    let session = EditorSession()

    let result = try session.execute(
        .createCircleSketch(
            name: "Round Profile",
            plane: .xy,
            center: SketchPoint(
                x: .length(3.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            radius: .length(8.0, .millimeter)
        ),
        expectedGeneration: DocumentGeneration(0)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let circle = try #require(sketch.entities.values.first)
    guard case .circle = circle else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "createCircleSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(feature.name == "Round Profile")
    #expect(sketch.entities.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@MainActor
@Test func extrudedRectangleCommandCreatesEvaluatedBodyAndSceneReferences() async throws {
    let session = EditorSession()

    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Box",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let order = session.document.cadDocument.designGraph.order
    let sketchFeatureID = try #require(order.first)
    let extrudeFeatureID = try #require(order.last)
    let extrudeFeature = try #require(session.document.cadDocument.designGraph.nodes[extrudeFeatureID])
    guard case let .extrude(extrude) = extrudeFeature.operation else {
        #expect(Bool(false))
        return
    }
    let references = session.document.productMetadata.sceneNodes.values.compactMap(\.reference)

    #expect(order.count == 2)
    #expect(session.document.cadDocument.designGraph.dependencies == [
        DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID),
    ])
    #expect(extrude.profile.featureID == sketchFeatureID)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(references.contains(.sketch(sketchFeatureID)))
    #expect(references.contains(.body(extrudeFeatureID)))
    #expect(session.commandStack.canUndo)

    _ = try session.undo()
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.evaluatedBodyCount == 0)
    #expect(session.generation == DocumentGeneration(2))

    _ = try session.redo()
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.generation == DocumentGeneration(3))
}

@MainActor
@Test func extrudedCircleCommandCreatesEvaluatedBodyAndSceneReferences() async throws {
    let session = EditorSession()

    let result = try session.execute(
        .createExtrudedCircle(
            name: "Cylinder",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(8.0, .millimeter),
            depth: .length(12.0, .millimeter),
            direction: .normal
        )
    )

    let order = session.document.cadDocument.designGraph.order
    let sketchFeatureID = try #require(order.first)
    let extrudeFeatureID = try #require(order.last)
    let references = session.document.productMetadata.sceneNodes.values.compactMap(\.reference)

    #expect(result.commandName == "createExtrudedCircle")
    #expect(order.count == 2)
    #expect(session.document.cadDocument.designGraph.dependencies == [
        DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID),
    ])
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(references.contains(.sketch(sketchFeatureID)))
    #expect(references.contains(.body(extrudeFeatureID)))
    #expect(session.commandStack.canUndo)

    _ = try session.undo()
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.evaluatedBodyCount == 0)

    _ = try session.redo()
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func extrudeProfileCommandUsesExistingSketchReference() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .length(8.0, .millimeter),
            height: .length(4.0, .millimeter)
        )
    )
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)

    let result = try session.execute(
        .extrudeProfile(
            name: "Body",
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .length(2.0, .millimeter),
            direction: .symmetric
        )
    )

    #expect(result.commandName == "extrudeProfile")
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func extrudeProfileCommandUsesCircleSketchReference() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Round Profile",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)

    let result = try session.execute(
        .extrudeProfile(
            name: "Cylinder",
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .length(3.0, .millimeter),
            direction: .normal
        )
    )

    #expect(result.commandName == "extrudeProfile")
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func extrudeProfileCommandRejectsOpenLineSketchBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Open Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)

    var caught: EditorError?
    do {
        _ = try session.execute(
            .extrudeProfile(
                name: "Rejected",
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .length(2.0, .millimeter),
                direction: .normal
            )
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .referenceUnresolved)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluatedBodyCount == 0)
}

@MainActor
@Test func unresolvedExtrudeProfileFailsBeforeMutation() async throws {
    let session = EditorSession()

    var caught: EditorError?
    do {
        _ = try session.execute(
            .extrudeProfile(
                name: "Missing",
                profile: ProfileReference(featureID: FeatureID()),
                distance: .length(1.0, .millimeter),
                direction: .normal
            )
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .referenceUnresolved)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
}

@MainActor
@Test func componentCommandsCreateDefinitionAndInstanceThroughCommandPath() async throws {
    let session = EditorSession()
    let rootSceneNodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)

    let definitionResult = try session.execute(
        .createComponentDefinition(
            name: "  Frame  ",
            rootSceneNodeIDs: [rootSceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)
    #expect(definitionResult.commandName == "createComponentDefinition")
    #expect(definitionResult.generation == DocumentGeneration(1))
    #expect(definition.name == "Frame")
    #expect(definition.rootSceneNodeIDs == [rootSceneNodeID])

    let instanceResult = try session.execute(
        .createComponentInstance(
            name: "Frame Instance",
            definitionID: definition.id,
            localTransform: .identity
        )
    )
    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let instanceSceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .componentInstance(instance.id)
        }
    )

    #expect(instanceResult.commandName == "createComponentInstance")
    #expect(instanceResult.generation == DocumentGeneration(2))
    #expect(instance.definitionID == definition.id)
    #expect(instance.name == "Frame Instance")
    #expect(instanceSceneNode.name == "Frame Instance")
    #expect(session.commandStack.canUndo)

    _ = try session.undo()
    #expect(session.document.productMetadata.componentDefinitions[definition.id] != nil)
    #expect(session.document.productMetadata.componentInstances[instance.id] == nil)
    #expect(session.commandStack.canRedo)

    _ = try session.redo()
    #expect(session.document.productMetadata.componentInstances[instance.id] != nil)
    #expect(
        session.document.productMetadata.sceneNodes.values.contains {
            $0.reference == .componentInstance(instance.id)
        }
    )
}

@MainActor
@Test func componentStateCommandsMutateThroughCommandPath() async throws {
    let session = EditorSession()
    _ = try session.execute(.createComponentDefinition(name: "Panel", rootSceneNodeIDs: []))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)
    _ = try session.execute(
        .createComponentInstance(
            name: "Panel A",
            definitionID: definition.id,
            localTransform: .identity
        )
    )
    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .componentInstance(instance.id)
        }
    )

    _ = try session.execute(.setComponentInstanceVisibility(id: instance.id, isVisible: false))
    _ = try session.execute(.setComponentInstanceLock(id: instance.id, isLocked: true))
    _ = try session.execute(.setSceneNodeVisibility(id: sceneNode.id, isVisible: false))
    let result = try session.execute(.setSceneNodeLock(id: sceneNode.id, isLocked: true))

    let updatedInstance = try #require(session.document.productMetadata.componentInstances[instance.id])
    let updatedSceneNode = try #require(session.document.productMetadata.sceneNodes[sceneNode.id])
    #expect(result.commandName == "setSceneNodeLock")
    #expect(result.generation == DocumentGeneration(6))
    #expect(!updatedInstance.isVisible)
    #expect(updatedInstance.isLocked)
    #expect(!updatedSceneNode.isVisible)
    #expect(updatedSceneNode.isLocked)

    _ = try session.undo()
    let restoredSceneNode = try #require(session.document.productMetadata.sceneNodes[sceneNode.id])
    #expect(!restoredSceneNode.isVisible)
    #expect(!restoredSceneNode.isLocked)
}

@MainActor
@Test func componentTransformCommandsMutateThroughCommandPath() async throws {
    let session = EditorSession()
    _ = try session.execute(.createComponentDefinition(name: "Armature", rootSceneNodeIDs: []))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)
    _ = try session.execute(
        .createComponentInstance(
            name: "Armature A",
            definitionID: definition.id,
            localTransform: .identity
        )
    )
    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .componentInstance(instance.id)
        }
    )
    let instanceTransform = try translationTransform(x: 0.01, y: 0.02, z: 0.03)
    let sceneNodeTransform = try translationTransform(x: 0.04, y: 0.05, z: 0.06)

    let instanceResult = try session.execute(
        .setComponentInstanceTransform(
            id: instance.id,
            localTransform: instanceTransform
        )
    )
    let sceneNodeResult = try session.execute(
        .setSceneNodeTransform(
            id: sceneNode.id,
            localTransform: sceneNodeTransform
        )
    )

    #expect(instanceResult.commandName == "setComponentInstanceTransform")
    #expect(sceneNodeResult.commandName == "setSceneNodeTransform")
    #expect(sceneNodeResult.generation == DocumentGeneration(4))
    #expect(session.document.productMetadata.componentInstances[instance.id]?.localTransform == instanceTransform)
    #expect(session.document.productMetadata.sceneNodes[sceneNode.id]?.localTransform == sceneNodeTransform)
    #expect(session.evaluationStatus == .valid)

    _ = try session.undo()
    #expect(session.document.productMetadata.componentInstances[instance.id]?.localTransform == instanceTransform)
    #expect(session.document.productMetadata.sceneNodes[sceneNode.id]?.localTransform == .identity)

    _ = try session.undo()
    #expect(session.document.productMetadata.componentInstances[instance.id]?.localTransform == .identity)
}

@MainActor
@Test func componentCommandsRejectMissingReferencesBeforeMutation() async throws {
    let session = EditorSession()

    var instanceError: EditorError?
    do {
        _ = try session.execute(
            .createComponentInstance(
                name: "Missing",
                definitionID: ComponentDefinitionID(),
                localTransform: .identity
            )
        )
    } catch let error as EditorError {
        instanceError = error
    }

    var sceneNodeError: EditorError?
    do {
        _ = try session.execute(
            .setSceneNodeVisibility(id: SceneNodeID(), isVisible: false)
        )
    } catch let error as EditorError {
        sceneNodeError = error
    }

    var sceneNodeTransformError: EditorError?
    do {
        _ = try session.execute(
            .setSceneNodeTransform(
                id: SceneNodeID(),
                localTransform: .identity
            )
        )
    } catch let error as EditorError {
        sceneNodeTransformError = error
    }

    var componentInstanceError: EditorError?
    do {
        _ = try session.execute(
            .setComponentInstanceLock(id: ComponentInstanceID(), isLocked: true)
        )
    } catch let error as EditorError {
        componentInstanceError = error
    }

    var componentInstanceTransformError: EditorError?
    do {
        _ = try session.execute(
            .setComponentInstanceTransform(
                id: ComponentInstanceID(),
                localTransform: .identity
            )
        )
    } catch let error as EditorError {
        componentInstanceTransformError = error
    }

    #expect(instanceError?.code == .referenceUnresolved)
    #expect(sceneNodeError?.code == .referenceUnresolved)
    #expect(sceneNodeTransformError?.code == .referenceUnresolved)
    #expect(componentInstanceError?.code == .referenceUnresolved)
    #expect(componentInstanceTransformError?.code == .referenceUnresolved)
    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
}

@MainActor
@Test func componentTransformCommandsRejectInvalidTransformsBeforeMutation() async throws {
    let session = EditorSession()
    let rootSceneNodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)
    var invalidTransform = Transform3D.identity
    invalidTransform.matrix.values[12] = .infinity

    var didThrow = false
    do {
        _ = try session.execute(
            .setSceneNodeTransform(
                id: rootSceneNodeID,
                localTransform: invalidTransform
            )
        )
    } catch {
        didThrow = true
    }

    #expect(didThrow)
    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(!session.commandStack.canUndo)
    #expect(session.document.productMetadata.sceneNodes[rootSceneNodeID]?.localTransform == .identity)
}

@MainActor
@Test func initialSessionEvaluationIsExplicitlyDeferred() async throws {
    let session = EditorSession()

    #expect(session.evaluationStatus == .notEvaluated)
    #expect(session.evaluatedGeneration == nil)
    #expect(!session.renderInvalidation.requiresSceneRebuild)
}

private func sketchFeature(
    in document: DesignDocument,
    featureID: FeatureID
) -> Sketch? {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation else {
        return nil
    }
    return sketch
}

private func singleSketchEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) -> SketchEntityID? {
    guard let sketch = sketchFeature(in: document, featureID: featureID),
          sketch.entities.count == 1 else {
        return nil
    }
    return sketch.entities.keys.first
}

private func resolvedLinePoints(
    in sketch: Sketch,
    parameters: ParameterTable
) throws -> Set<Point2D> {
    var points: Set<Point2D> = []
    for entity in sketch.entities.values {
        guard case let .line(line) = entity else {
            continue
        }
        points.insert(try resolvedPoint(line.start, parameters: parameters))
        points.insert(try resolvedPoint(line.end, parameters: parameters))
    }
    return points
}

private func resolvedCircle(in sketch: Sketch) -> SketchCircle? {
    let circles = sketch.entities.values.compactMap { entity in
        if case .circle(let circle) = entity {
            return circle
        }
        return nil
    }
    return circles.count == 1 ? circles[0] : nil
}

private func resolvedPoint(
    _ point: SketchPoint,
    parameters: ParameterTable
) throws -> Point2D {
    let x = try parameters.resolvedValue(for: point.x)
    let y = try parameters.resolvedValue(for: point.y)
    #expect(x.kind == .length)
    #expect(y.kind == .length)
    return Point2D(x: x.value, y: y.value)
}

private func resolvedLength(
    _ expression: CADExpression,
    parameters: ParameterTable
) throws -> Double {
    let quantity = try parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}

private func translationTransform(
    x: Double,
    y: Double,
    z: Double
) throws -> Transform3D {
    Transform3D(
        matrix: try Matrix4x4(
            values: [
                1.0, 0.0, 0.0, x,
                0.0, 1.0, 0.0, y,
                0.0, 0.0, 1.0, z,
                0.0, 0.0, 0.0, 1.0,
            ]
        )
    )
}

@MainActor
@Test func evaluationFailurePublishesDiagnosticsAndRenderInvalidation() async throws {
    let missingFeatureID = FeatureID()
    let document = DesignDocument(
        cadDocument: CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [:],
                order: [missingFeatureID]
            )
        ),
        displayUnit: .millimeter,
        ruler: .standard(for: .millimeter)
    )
    let session = EditorSession(document: document)

    let result = try session.execute(.validateDocument)

    guard case .failed(let message) = session.evaluationStatus else {
        #expect(Bool(false))
        return
    }
    #expect(!result.didMutate)
    #expect(result.generation == DocumentGeneration(0))
    #expect(message.contains("Feature order must contain every node exactly once."))
    #expect(session.diagnostics.first?.severity == .error)
    #expect(session.evaluatedGeneration == DocumentGeneration(0))
    #expect(session.renderInvalidation == RenderInvalidation(
        generation: DocumentGeneration(0),
        reason: .evaluationFailed
    ))
}

@MainActor
@Test func fileServiceRoundTripsPersistedDocumentMetadata() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer {
        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error)")
        }
    }

    let url = temporaryDirectory.appendingPathComponent("roundtrip.swcad")
    let service = DocumentFileService()
    var document = DesignDocument.empty(named: "Before")
    document.rename("After")

    try service.save(document, to: url)
    let loaded = try service.load(from: url)

    #expect(loaded.cadDocument.metadata.name == "After")
}
