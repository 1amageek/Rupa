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
@Test func editorSessionExposesCurrentEvaluatedDocumentForMatchingGeneration() async throws {
    let session = EditorSession()

    _ = try #require(session.createDefaultExtrudedRectangle())

    let evaluationCache = try #require(session.currentEvaluationCache)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedGeneration == session.generation)
    #expect(evaluationCache.generation == session.generation)
    #expect(evaluationCache.evaluatedDocument.meshes.count == session.evaluatedBodyCount)

    session.reportToolStatus("Cache-preserving diagnostic")
    #expect(session.currentEvaluationCache != nil)

    let snapshot = session.store.snapshot()
    session.store.restore(DocumentSnapshot(
        document: snapshot.document,
        generation: snapshot.generation,
        isDirty: snapshot.isDirty,
        diagnostics: snapshot.diagnostics,
        evaluationStatus: .failed(message: "Injected failure"),
        evaluatedGeneration: snapshot.evaluatedGeneration,
        renderInvalidation: snapshot.renderInvalidation,
        evaluatedBodyCount: snapshot.evaluatedBodyCount
    ))
    #expect(session.currentEvaluationCache == nil)
}

@MainActor
@Test func editorSessionRebuildsEvaluationCacheAfterUndoAndRedo() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let originalGeneration = session.generation
    let originalCache = try #require(session.currentEvaluationCache)

    _ = try session.execute(.setDisplayUnit(.meter))
    let changedCache = try #require(session.currentEvaluationCache)
    #expect(changedCache.generation == session.generation)
    #expect(changedCache.generation != originalCache.generation)

    _ = try session.undo()
    let undoCache = try #require(session.currentEvaluationCache)
    #expect(session.generation != originalGeneration)
    #expect(undoCache.generation == session.generation)
    #expect(undoCache.sourceFingerprint == originalCache.sourceFingerprint)

    _ = try session.redo()
    let redoCache = try #require(session.currentEvaluationCache)
    #expect(redoCache.generation == session.generation)
    #expect(redoCache.sourceFingerprint == changedCache.sourceFingerprint)
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
@Test func measurementServiceMeasuresOffsetFaceLoopDirectEditSolid() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let componentID = try #require(
        try GeneratedTopologySelectionResolver().componentID(
            for: bodySceneNodeID,
            bodyFace: .front,
            in: session.document
        )
    )
    let target = SelectionTarget(sceneNodeID: bodySceneNodeID, component: .face(componentID))

    _ = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .linear),
            vertexHandle: nil
        )
    )

    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let result = try MeasurementService().measure(document: session.document)
    let solid = try #require(result.solids.first { $0.featureID == offsetFeatureID.description })
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)
    let bounds = try #require(result.bounds)

    #expect(result.counts.solids == 1)
    #expect(result.counts.profiles == 1)
    #expect(result.solids.contains { $0.featureID == bodyFeatureID.description } == false)
    #expect(abs(solid.volumeCubicMeters - 0.000008) < 1.0e-12)
    #expect(abs(result.totals.solidVolumeCubicMeters - solid.volumeCubicMeters) < 1.0e-12)
    #expect(surfaceArea > 0.0)
    #expect(abs(bounds.sizeX - 0.04) < 1.0e-12)
    #expect(abs(bounds.sizeY - 0.02) < 1.0e-12)
    #expect(abs(bounds.sizeZ - 0.01) < 1.0e-12)
    #expect(result.diagnostics.contains { $0.message.contains("Offset Face Loop") } == false)
}

@MainActor
@Test func measurementServiceMeasuresOffsetEdgeDirectEditSolid() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let supportFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(
        topology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.curveKind == "line" &&
                commandStackTopologyPoint($0.start, isOnDepth: supportDepth) &&
                commandStackTopologyPoint($0.end, isOnDepth: supportDepth) &&
                $0.selectionTarget() != nil
        }
    )
    let target = try #require(edgeEntry.selectionTarget())

    _ = try session.execute(
        .offsetCurve(
            target: target,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(
                gapFill: .linear,
                supportTarget: supportFaceTarget
            ),
            vertexHandle: nil
        )
    )

    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let result = try MeasurementService().measure(document: session.document)
    let solid = try #require(result.solids.first { $0.featureID == offsetFeatureID.description })
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)
    let bounds = try #require(result.bounds)

    #expect(result.counts.solids == 1)
    #expect(result.counts.profiles == 1)
    #expect(result.solids.contains { $0.featureID == bodyFeatureID.description } == false)
    #expect(abs(solid.volumeCubicMeters - 0.000008) < 1.0e-12)
    #expect(abs(result.totals.solidVolumeCubicMeters - solid.volumeCubicMeters) < 1.0e-12)
    #expect(surfaceArea > 0.0)
    #expect(abs(bounds.sizeX - 0.04) < 1.0e-12)
    #expect(abs(bounds.sizeY - 0.02) < 1.0e-12)
    #expect(abs(bounds.sizeZ - 0.01) < 1.0e-12)
    #expect(result.diagnostics.contains { $0.message.contains("Offset Edge") } == false)
}

@MainActor
@Test func editorSessionInfersOffsetEdgeSupportFaceFromSelectionContext() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let supportFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(
        topology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.curveKind == "line" &&
                commandStackTopologyPoint($0.start, isOnDepth: supportDepth) &&
                commandStackTopologyPoint($0.end, isOnDepth: supportDepth) &&
                $0.selectionTarget() != nil
        }
    )
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    #expect(session.selectTargets([supportFaceTarget, edgeTarget]))
    let result = try session.execute(
        .offsetCurve(
            target: edgeTarget,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .linear),
            vertexHandle: nil
        )
    )

    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Selection-context Offset Curve edge target must create an EdgeOffset feature.")
        return
    }
    guard case .face(let supportComponentID) = supportFaceTarget.component,
          let supportPersistentNameString = supportComponentID.generatedTopologyPersistentName else {
        Issue.record("Support target must be a generated topology face target.")
        return
    }
    let expectedSupportPersistentName = try GeneratedTopologyPersistentNameParser().parse(
        supportPersistentNameString,
        operationName: "Offset Edge"
    )

    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.supportFacePersistentName == expectedSupportPersistentName)
    #expect(edgeOffset.gapFill == .linear)
    #expect(session.selection.selectedTargets == [supportFaceTarget, edgeTarget])
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionInfersOffsetEdgeCapSupportFaceFromSingleSelectedEdge() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let supportFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(
        topology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.curveKind == "line" &&
                commandStackTopologyPoint($0.start, isOnDepth: supportDepth) &&
                commandStackTopologyPoint($0.end, isOnDepth: supportDepth) &&
                $0.selectionTarget() != nil
        }
    )
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    #expect(session.selectTargets([edgeTarget]))
    let result = try session.execute(
        .offsetCurve(
            target: edgeTarget,
            distance: .length(2.0, .millimeter),
            options: OffsetCurveOptions(gapFill: .linear),
            vertexHandle: nil
        )
    )

    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Single selected cap edge Offset Curve must create an EdgeOffset feature.")
        return
    }
    let expectedSupportPersistentName = try GeneratedTopologyPersistentNameParser().parse(
        supportFaceEntry.persistentName,
        operationName: "Offset Edge"
    )

    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.supportFacePersistentName == expectedSupportPersistentName)
    #expect(edgeOffset.gapFill == .linear)
    #expect(session.selection.selectedTargets == [edgeTarget])
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func edgeOffsetSupportFaceResolverReportsSelectedSupportFaceSource() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let supportFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(
        topology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.curveKind == "line" &&
                commandStackTopologyPoint($0.start, isOnDepth: supportDepth) &&
                commandStackTopologyPoint($0.end, isOnDepth: supportDepth) &&
                $0.selectionTarget() != nil
        }
    )
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    #expect(session.selectTargets([supportFaceTarget, edgeTarget]))
    let resolution = try EdgeOffsetSupportFaceResolver().resolve(
        edgeTarget: edgeTarget,
        selection: session.selection,
        document: session.document,
        objectRegistry: session.objectRegistry
    )

    #expect(resolution.status == .supported)
    #expect(resolution.source == .selectedFace)
    #expect(resolution.supportTarget == supportFaceTarget)
}

@MainActor
@Test func edgeOffsetSupportFaceResolverReportsInferredCapFaceSource() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let supportFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(
        topology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.curveKind == "line" &&
                commandStackTopologyPoint($0.start, isOnDepth: supportDepth) &&
                commandStackTopologyPoint($0.end, isOnDepth: supportDepth) &&
                $0.selectionTarget() != nil
        }
    )
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    #expect(session.selectTargets([edgeTarget]))
    let resolution = try EdgeOffsetSupportFaceResolver().resolve(
        edgeTarget: edgeTarget,
        selection: session.selection,
        document: session.document,
        objectRegistry: session.objectRegistry
    )

    #expect(resolution.status == .supported)
    #expect(resolution.source == .inferredCapFace)
    #expect(resolution.supportTarget == supportFaceTarget)
}

@MainActor
@Test func edgeOffsetSupportFaceResolverReportsAmbiguousSelectedSupportFaces() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let faceTargets = topology.entries
        .filter {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.selectionTarget() != nil
        }
        .compactMap { $0.selectionTarget() }
    let firstFaceTarget = try #require(faceTargets.first)
    let secondFaceTarget = try #require(faceTargets.dropFirst().first)
    let edgeEntry = try #require(
        topology.entries.first {
            $0.kind == .edge &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.curveKind == "line" &&
                $0.selectionTarget() != nil
        }
    )
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    #expect(session.selectTargets([firstFaceTarget, secondFaceTarget, edgeTarget]))
    let resolution = try EdgeOffsetSupportFaceResolver().resolve(
        edgeTarget: edgeTarget,
        selection: session.selection,
        document: session.document,
        objectRegistry: session.objectRegistry
    )

    #expect(resolution.status == .ambiguous)
    #expect(resolution.supportTarget == nil)
    #expect(resolution.diagnosticMessage == EdgeOffsetSupportFaceResolver.ambiguousSelectedSupportFaceMessage)
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
@Test func measurementServiceIncludesSplineSketchBounds() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Measured Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )

    let result = try MeasurementService().measure(document: session.document)
    let bounds = try #require(result.bounds)

    #expect(result.counts.sourceFeatures == 1)
    #expect(result.counts.sketches == 1)
    #expect(result.counts.sketchPrimitives == 1)
    #expect(result.counts.profiles == 0)
    #expect(abs(bounds.minX) <= 1.0e-12)
    #expect(abs(bounds.maxX - 0.008) <= 1.0e-12)
    #expect(bounds.maxY > 0.002)
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
@Test func measurementServiceMeasuresExtrudedSplineAreaAndVolume() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Spline Profile",
            plane: .xy,
            spline: closedBezierCircleSpline(radius: 10.0, unit: .millimeter)
        )
    )
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    _ = try session.execute(
        .extrudeProfile(
            name: "Spline Body",
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .length(5.0, .millimeter),
            direction: .normal
        )
    )

    let result = try MeasurementService().measure(document: session.document)
    let area = result.totals.profileAreaSquareMeters

    #expect(result.profiles.first?.kind == .curveLoop)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 1)
    #expect(abs(area - Double.pi * 0.0001) < 1.0e-7)
    #expect(abs(result.totals.solidVolumeCubicMeters - area * 0.005) < 1.0e-12)
}

@MainActor
@Test func measurementServiceMeasuresSupportedStraightPathSweepAreaAndVolume() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Measured Sweep Profile",
            plane: .xy,
            width: .length(4.0, .millimeter),
            height: .length(2.0, .millimeter)
        )
    )
    let profileID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createLineSketch(
            name: "Measured Sweep Path",
            plane: .yz,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createSweep(
            name: "Measured Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [],
            targets: [],
            options: SweepOptions()
        )
    )
    let result = try MeasurementService().measure(document: session.document)
    let solid = try #require(result.solids.first)
    let normalHeight = try linearDimensionMeters(.sweepNormalHeight, in: solid)
    let pathLength = try linearDimensionMeters(.sweepPathLength, in: solid)
    let bounds = try #require(result.bounds)

    #expect(result.counts.sketches == 2)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 1)
    #expect(abs(result.totals.profileAreaSquareMeters - 0.000008) < 1.0e-12)
    #expect(abs(result.totals.solidVolumeCubicMeters - 0.00000016) < 1.0e-12)
    #expect(abs(normalHeight - 0.02) < 1.0e-12)
    #expect(abs(pathLength - 0.02) < 1.0e-12)
    #expect(abs(bounds.sizeX - 0.004) < 1.0e-12)
    #expect(abs(bounds.sizeY - 0.002) < 1.0e-12)
    #expect(abs(bounds.sizeZ - 0.02) < 1.0e-12)
    #expect(result.diagnostics.isEmpty)
}

@MainActor
@Test func measurementServiceMeasuresCurvedPathSweepFromEvaluatedMesh() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Measured Curved Sweep Profile",
            plane: .xy,
            width: .length(4.0, .millimeter),
            height: .length(2.0, .millimeter)
        )
    )
    let profileID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createArcSketch(
            name: "Measured Curved Sweep Path",
            plane: .yz,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(60.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createSweep(
            name: "Measured Curved Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [],
            targets: [],
            options: SweepOptions()
        )
    )

    let result = try MeasurementService().measure(document: session.document)
    let solid = try #require(result.solids.first)
    let bounds = try #require(result.bounds)
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)
    let pathLength = try linearDimensionMeters(.sweepPathLength, in: solid)
    let expectedPathLength = 0.060 * Double.pi / 2.0
    let expectedVolume = 0.004 * 0.002 * expectedPathLength

    #expect(result.counts.sketches == 2)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 1)
    #expect(abs(result.totals.profileAreaSquareMeters - 0.000008) < 1.0e-12)
    #expect(abs(pathLength - expectedPathLength) < 1.0e-12)
    #expect(abs(solid.volumeCubicMeters - expectedVolume) < 1.0e-8)
    #expect(abs(result.totals.solidVolumeCubicMeters - solid.volumeCubicMeters) < 1.0e-12)
    #expect(surfaceArea > 0.001)
    #expect(bounds.sizeY > 0.05)
    #expect(bounds.sizeZ > 0.05)
    #expect(result.diagnostics.isEmpty)
}

@MainActor
@Test func measurementServiceMeasuresTwistedScaledSweepFromEvaluatedMesh() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Measured Twisted Sweep Profile",
            plane: .xy,
            width: .length(4.0, .millimeter),
            height: .length(2.0, .millimeter)
        )
    )
    let profileID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createLineSketch(
            name: "Measured Twisted Sweep Path",
            plane: .yz,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createSweep(
            name: "Measured Twisted Scaled Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [],
            targets: [],
            options: SweepOptions(
                twistAngle: .angle(90.0, .degree),
                endScale: .constant(.scalar(0.5))
            )
        )
    )

    let result = try MeasurementService().measure(document: session.document)
    #expect(result.diagnostics.map(\.message) == [])
    let solid = try #require(result.solids.first)
    let pathLength = try linearDimensionMeters(.sweepPathLength, in: solid)
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)

    #expect(result.counts.sketches == 2)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 1)
    #expect(abs(pathLength - 0.02) < 1.0e-12)
    #expect(solid.volumeCubicMeters > 0.0)
    #expect(solid.volumeCubicMeters < 0.00000016)
    #expect(surfaceArea > 0.0)
    #expect(result.diagnostics.isEmpty)
}

@MainActor
@Test func measurementServiceMeasuresPointGuidedSweepFromEvaluatedMesh() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Measured Guided Sweep Profile",
            plane: .xy,
            width: .length(4.0, .millimeter),
            height: .length(2.0, .millimeter)
        )
    )
    let profileID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createLineSketch(
            name: "Measured Guided Sweep Path",
            plane: .yz,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createLineSketch(
            name: "Measured Guided Sweep Guide",
            plane: .yz,
            start: SketchPoint(
                x: .length(1.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let guideID = try #require(session.document.cadDocument.designGraph.order.last)
    let sweepResult = try session.execute(
        .createSweep(
            name: "Measured Point Guided Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [SweepGuideReference(featureID: guideID)],
            targets: [],
            options: SweepOptions(guideMethod: .point)
        )
    )

    #expect(sweepResult.didMutate)
    let result = try MeasurementService().measure(document: session.document)
    #expect(result.diagnostics.map(\.message) == [])
    #expect(result.counts.sourceFeatures == 4)
    let solid = try #require(result.solids.first)
    let pathLength = try linearDimensionMeters(.sweepPathLength, in: solid)
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)

    #expect(result.counts.sketches == 3)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 1)
    #expect(abs(pathLength - 0.02) < 1.0e-12)
    #expect(solid.volumeCubicMeters > 0.00000016)
    #expect(surfaceArea > 0.0)
}

@MainActor
@Test func measurementServiceMeasuresMultiplePointGuidedSweepFromEvaluatedMesh() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Measured Multi Guided Sweep Profile",
            plane: .xy,
            width: .length(4.0, .millimeter),
            height: .length(2.0, .millimeter)
        )
    )
    let profileID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createLineSketch(
            name: "Measured Multi Guided Sweep Path",
            plane: .yz,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createLineSketch(
            name: "Measured Multi Guided Sweep Top Guide",
            plane: .yz,
            start: SketchPoint(
                x: .length(1.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let topGuideID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createLineSketch(
            name: "Measured Nonuniform Rail Sweep Right Guide",
            plane: .zx,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(3.0, .millimeter)
            )
        )
    )
    let rightGuideID = try #require(session.document.cadDocument.designGraph.order.last)
    _ = try session.execute(
        .createSweep(
            name: "Measured Multiple Point Guided Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [
                SweepGuideReference(featureID: topGuideID),
                SweepGuideReference(featureID: rightGuideID),
            ],
            targets: [],
            options: SweepOptions(guideMethod: .point)
        )
    )

    let result = try MeasurementService().measure(document: session.document)
    let solid = try #require(result.solids.first)
    let pathLength = try linearDimensionMeters(.sweepPathLength, in: solid)
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)

    #expect(result.counts.sketches == 4)
    #expect(result.counts.profiles == 1)
    #expect(result.counts.solids == 1)
    #expect(abs(pathLength - 0.02) < 1.0e-12)
    #expect(solid.volumeCubicMeters > 0.00000016)
    #expect(surfaceArea > 0.0)
    #expect(result.diagnostics.isEmpty)
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
@Test func editorSessionCreatesSavedConstructionPlaneAndUsesItForDefaultSketches() async throws {
    let session = EditorSession()

    let planeResult = try #require(
        session.createConstructionPlane(
            name: "Right CPlane",
            plane: .yz
        )
    )

    #expect(planeResult.commandName == "createConstructionPlane")
    #expect(planeResult.didMutate)
    #expect(session.generation == DocumentGeneration(1))
    let summary = ConstructionPlaneSummaryService().summarize(document: session.document)
    let entry = try #require(summary.planes.first)
    #expect(entry.name == "Right CPlane")
    #expect(entry.plane == .yz)
    #expect(entry.isActive)
    #expect(summary.activePlaneID == entry.id)
    #expect(entry.sceneNodeID != nil)
    #expect(session.activeSketchPlane() == .yz)
    #expect(session.document.productMetadata.sceneNodes.values.contains { node in
        node.reference?.constructionPlaneID == entry.id &&
            node.object?.category == .construction
    })

    let sketchResult = try #require(session.createDefaultRectangleSketch())

    #expect(sketchResult.commandName == "createRectangleSketch")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.designGraph.nodes.values.contains { feature in
        guard case .sketch(let sketch) = feature.operation else {
            return false
        }
        return sketch.plane == .yz
    })
}

@MainActor
@Test func editorSessionSwitchesAndClearsActiveConstructionPlane() async throws {
    let session = EditorSession()

    _ = try #require(
        session.createConstructionPlane(
            name: "Plane A",
            plane: .xy,
            activates: false
        )
    )
    let firstID = try #require(
        session.document.productMetadata.constructionPlanes.values.first { $0.name == "Plane A" }?.id
    )
    _ = try #require(
        session.createConstructionPlane(
            name: "Plane B",
            plane: .zx
        )
    )
    #expect(session.activeConstructionPlane?.name == "Plane B")

    let activateResult = try #require(session.setActiveConstructionPlane(id: firstID))

    #expect(activateResult.commandName == "setActiveConstructionPlane")
    #expect(session.activeConstructionPlane?.name == "Plane A")
    #expect(session.activeSketchPlane() == .xy)

    let clearResult = try #require(session.setActiveConstructionPlane(id: nil))

    #expect(clearResult.commandName == "setActiveConstructionPlane")
    #expect(session.activeConstructionPlane == nil)
    #expect(session.activeSketchPlane(fallback: .yz) == .yz)
}

@MainActor
@Test func editorSessionRenamesSavedConstructionPlaneAndLinkedSceneNode() async throws {
    let session = EditorSession()

    _ = try #require(
        session.createConstructionPlane(
            name: "Plane A",
            plane: .xy
        )
    )
    _ = try #require(
        session.createConstructionPlane(
            name: "Plane B",
            plane: .yz,
            activates: false
        )
    )
    let planeID = try #require(
        session.document.productMetadata.constructionPlanes.values.first { $0.name == "Plane A" }?.id
    )

    let renameResult = try #require(
        session.renameConstructionPlane(
            id: planeID,
            name: "Renamed Plane"
        )
    )

    #expect(renameResult.commandName == "renameConstructionPlane")
    #expect(renameResult.didMutate)
    #expect(session.activeConstructionPlane?.name == "Renamed Plane")
    let summary = ConstructionPlaneSummaryService().summarize(document: session.document)
    let entry = try #require(summary.planes.first { $0.id == planeID })
    #expect(entry.name == "Renamed Plane")
    let sceneNodeID = try #require(entry.sceneNodeID)
    #expect(session.document.productMetadata.sceneNodes[sceneNodeID]?.name == "Renamed Plane")

    #expect(throws: EditorError.self) {
        try session.execute(
            .renameConstructionPlane(
                id: planeID,
                name: "Plane B"
            )
        )
    }
    #expect(session.document.productMetadata.constructionPlanes[planeID]?.name == "Renamed Plane")
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
@Test func editorSessionActivatesSweepToolFromSelectedProfileAndCanvasPathTarget() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultRectangleSketch())
    let profileFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let profileNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(profileFeatureID)
    }?.key)
    _ = try session.execute(
        .createLineSketch(
            name: "Sweep Path",
            plane: .yz,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let pathFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let pathNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(pathFeatureID)
    }?.key)

    _ = session.selectSceneNode(profileNodeID)
    session.selectTool(.sweep)
    let result = session.activateSelectedToolFromCanvas(targetSceneNodeID: pathNodeID)
    let sweepFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sweepFeature = try #require(session.document.cadDocument.designGraph.nodes[sweepFeatureID])
    guard case .sweep(let sweep) = sweepFeature.operation else {
        Issue.record("Sweep tool should create a sweep feature.")
        return
    }

    #expect(result.tool == .sweep)
    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(sweep.sections == [.profile(ProfileReference(featureID: profileFeatureID))])
    #expect(sweep.path == SweepPathReference(featureID: pathFeatureID))
    #expect(session.selectedSceneNode?.reference == .body(sweepFeatureID))
    #expect(session.selectedTool == .select)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func editorSessionActivatesSweepToolFromSelectedCurveSectionAndCanvasPathTarget() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Sweep Curve Section",
            plane: .xy,
            start: SketchPoint(
                x: .length(-2.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let sectionFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sectionNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(sectionFeatureID)
    }?.key)
    _ = try session.execute(
        .createLineSketch(
            name: "Sweep Curve Path",
            plane: .yz,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let pathFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let pathNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(pathFeatureID)
    }?.key)

    _ = session.selectSceneNode(sectionNodeID)
    session.selectTool(.sweep)
    let preview = session.sweepSelectionPreview(targetSceneNodeID: pathNodeID)
    let result = session.activateSelectedToolFromCanvas(targetSceneNodeID: pathNodeID)
    let sweepFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sweepFeature = try #require(session.document.cadDocument.designGraph.nodes[sweepFeatureID])
    let bodySceneNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(sweepFeatureID)
    })

    guard case .sweep(let sweep) = sweepFeature.operation else {
        Issue.record("Sweep tool should create a curve-section sheet sweep feature.")
        return
    }

    #expect(preview.status == .ready)
    #expect(preview.section == .curve(SweepCurveSectionReference(featureID: sectionFeatureID)))
    #expect(preview.pathFeatureID == pathFeatureID)
    #expect(result.tool == .sweep)
    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(sweep.sections == [.curve(SweepCurveSectionReference(featureID: sectionFeatureID))])
    #expect(sweep.path == SweepPathReference(featureID: pathFeatureID))
    #expect(sweep.options.resultKind == .sheet)
    #expect(sweepFeature.outputs == [FeatureOutput(role: .sheet)])
    #expect(bodySceneNode.object?.sourceSection == .curve(sectionFeatureID))
    #expect(session.selectedSceneNode?.reference == .body(sweepFeatureID))
    #expect(session.selectedTool == .select)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func editorSessionActivatesSweepToolFromSelectedGeneratedCurveFeatureAndCanvasPathTarget() async throws {
    var document = DesignDocument.empty()
    let sourceSectionID = try document.createLineSketch(
        name: "Generated Sweep Source Section",
        plane: .xy,
        start: SketchPoint(
            x: .length(-2.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(2.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let generatedSectionID = FeatureID()
    let generatedSection = FeatureNode(
        id: generatedSectionID,
        name: "Generated Offset Section",
        operation: .curveOffset(CurveOffsetFeature(
            source: CurveOutputReference(featureID: sourceSectionID),
            distance: .length(1.0, .millimeter),
            planeNormal: .unitZ
        )),
        inputs: [FeatureInput(featureID: sourceSectionID, role: .curve)],
        outputs: [FeatureOutput(role: .curve)]
    )
    try document.cadDocument.appendFeature(generatedSection)
    let generatedNodeID = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Generated Offset Section",
        reference: .feature(generatedSectionID)
    )
    let pathID = try document.createLineSketch(
        name: "Generated Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let pathNodeID = try #require(document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(pathID)
    }?.key)
    try document.validate()
    let session = EditorSession(document: document)

    _ = session.selectSceneNode(generatedNodeID)
    session.selectTool(.sweep)
    let preview = session.sweepSelectionPreview(targetSceneNodeID: pathNodeID)
    let result = session.activateSelectedToolFromCanvas(targetSceneNodeID: pathNodeID)
    let sweepFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sweepFeature = try #require(session.document.cadDocument.designGraph.nodes[sweepFeatureID])
    let bodySceneNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(sweepFeatureID)
    })

    guard case .sweep(let sweep) = sweepFeature.operation else {
        Issue.record("Sweep tool should create a generated-curve sheet sweep feature.")
        return
    }

    #expect(preview.status == .ready)
    #expect(preview.section == .curve(SweepCurveSectionReference(featureID: generatedSectionID)))
    #expect(preview.pathFeatureID == pathID)
    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(sweep.sections == [.curve(SweepCurveSectionReference(featureID: generatedSectionID))])
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(sweep.options.resultKind == .sheet)
    #expect(bodySceneNode.object?.sourceSection == .curve(generatedSectionID))
    #expect(session.selectedSceneNode?.reference == .body(sweepFeatureID))
    #expect(session.selectedTool == .select)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func editorSessionSweepToolCreatesGuideReferencesFromSelectedCurvesAndClickedPath() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultRectangleSketch())
    let profileFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let profileNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(profileFeatureID)
    }?.key)
    _ = try session.execute(
        .createLineSketch(
            name: "Sweep Guide",
            plane: .yz,
            start: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let guideFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let guideNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(guideFeatureID)
    }?.key)
    _ = try session.execute(
        .createLineSketch(
            name: "Sweep Path",
            plane: .yz,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(20.0, .millimeter)
            )
        )
    )
    let pathFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let pathNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(pathFeatureID)
    }?.key)

    _ = session.selectTargets([
        SelectionTarget(sceneNodeID: profileNodeID),
        SelectionTarget(sceneNodeID: guideNodeID),
    ])
    session.selectTool(.sweep)
    let preview = session.sweepSelectionPreview(targetSceneNodeID: pathNodeID)
    let result = session.activateSelectedToolFromCanvas(targetSceneNodeID: pathNodeID)
    let sweepFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sweepFeature = try #require(session.document.cadDocument.designGraph.nodes[sweepFeatureID])
    guard case .sweep(let sweep) = sweepFeature.operation else {
        Issue.record("Sweep tool should create a guided sweep source.")
        return
    }

    #expect(preview.status == .ready)
    #expect(preview.profileFeatureID == profileFeatureID)
    #expect(preview.pathFeatureID == pathFeatureID)
    #expect(preview.guideFeatureIDs == [guideFeatureID])
    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(sweep.sections == [.profile(ProfileReference(featureID: profileFeatureID))])
    #expect(sweep.path == SweepPathReference(featureID: pathFeatureID))
    #expect(sweep.guides == [SweepGuideReference(featureID: guideFeatureID)])
    #expect(sweepFeature.inputs == [
        FeatureInput(featureID: profileFeatureID, role: .profile),
        FeatureInput(featureID: pathFeatureID, role: .path),
        FeatureInput(featureID: guideFeatureID, role: .guide),
    ])
    #expect(session.selectedSceneNode?.reference == .body(sweepFeatureID))
    #expect(session.selectedTool == .select)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func editorSessionSweepToolRejectsMissingPathBeforeMutation() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultRectangleSketch())
    let profileFeatureID = try #require(session.document.cadDocument.designGraph.order.first)
    let profileNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(profileFeatureID)
    }?.key)
    _ = session.selectSceneNode(profileNodeID)
    session.selectTool(.sweep)
    let generation = session.generation
    let preview = session.sweepSelectionPreview()

    let result = session.activateSelectedToolFromCanvas(targetSceneNodeID: nil)

    #expect(preview.status == .missingPath)
    #expect(preview.profileFeatureID == profileFeatureID)
    #expect(preview.pathFeatureID == nil)
    #expect(result.tool == .sweep)
    #expect(!result.didMutate)
    #expect(result.revealsDiagnostics)
    #expect(session.generation == generation)
    #expect(session.selectedTool == .sweep)
    #expect(session.document.cadDocument.designGraph.order == [profileFeatureID])
    #expect(session.diagnostics.last?.message == "Sweep tool requires one profile or curve section source, one separate path curve source, and optional guide curve selections.")
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
@Test func editorSessionPolygonToolUsesConfiguredStateFromCanvasBackground() async throws {
    let session = EditorSession()

    #expect(session.setPolygonSideCount(8))
    #expect(session.setPolygonSizingMode(.inradius) == .inradius)
    #expect(session.setPolygonInclinationMode(.horizontal) == .horizontal)
    session.selectTool(.polygon)

    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: -0.04, y: 0.025)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas click should create a polygon sketch feature.")
        return
    }

    #expect(result.commandName == "createPolygonSketch")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    #expect(sketch.entities.count == 8)
    #expect(session.polygonToolState.sideCount == 8)
    #expect(session.polygonToolState.sizingMode == .inradius)
    #expect(session.polygonToolState.inclinationMode == .horizontal)
    #expect(session.selectedSceneNode?.object?.properties["radius.is.inradius"] == .boolean(true))
    #expect(session.selectedSceneNode?.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.horizontal.rawValue))
    #expect(session.selectedSceneNode?.object?.properties["angle"] == .angle(22.5))

    session.selectTool(.polygon)
    let secondResult = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.04, y: -0.025)
    )
    let secondFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let secondFeature = try #require(session.document.cadDocument.designGraph.nodes[secondFeatureID])
    guard case let .sketch(secondSketch) = secondFeature.operation else {
        Issue.record("Second canvas click should create a polygon sketch feature.")
        return
    }

    #expect(secondResult.didMutate)
    #expect(secondSketch.entities.count == 8)
    #expect(session.polygonToolState.sideCount == 8)
    #expect(session.polygonToolState.inclinationMode == .horizontal)
}

@MainActor
@Test func editorSessionPolygonToolTogglesDocBackedKeyboardState() async throws {
    let session = EditorSession(selectedTool: .polygon)

    #expect(session.adjustPolygonSideCount(by: 1))
    #expect(session.polygonToolState.sideCount == PolygonToolState.defaultSideCount + 1)
    #expect(session.togglePolygonSizingMode() == .inradius)
    #expect(session.togglePolygonInclinationMode() == .horizontal)
    #expect(session.togglePolygonCutsFaces())
    #expect(session.togglePolygonCutsFaces() == false)

    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.0, y: 0.0),
        endModelPoint: Point2D(x: 0.02, y: 0.02)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let node = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })

    #expect(result.didMutate)
    #expect(node.object?.properties["sides.x"] == .integer(PolygonToolState.defaultSideCount + 1))
    #expect(node.object?.properties["radius.is.inradius"] == .boolean(true))
    #expect(node.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.horizontal.rawValue))
}

@MainActor
@Test func editorSessionPolygonKnifeCutsSelectedGeneratedFaceFromCanvas() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let startFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "startFace"
        }
    )
    let faceTarget = try #require(startFaceEntry.selectionTarget())

    #expect(session.selectTarget(faceTarget))
    #expect(session.setPolygonSideCount(4))
    #expect(session.setPolygonCutsFaces(true))
    session.selectTool(.polygon)

    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.0, y: 0.0),
        endModelPoint: Point2D(x: 0.005, y: 0.0),
        sketchPlane: .xy
    )

    let faceKnifeFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let faceKnifeSceneNodeID = try #require(
        commandStackBodySceneNodeID(for: faceKnifeFeatureID, in: session.document)
    )
    let feature = try #require(session.document.cadDocument.designGraph.nodes[faceKnifeFeatureID])
    guard case .faceKnife = feature.operation else {
        Issue.record("Polygon Knife should create a source-owned Face Knife feature.")
        return
    }
    let afterTopology = try TopologySummaryService().summarize(document: session.document)
    let faceKnifeFaces = afterTopology.entries.filter {
        $0.kind == .face && $0.sceneNodeID == faceKnifeSceneNodeID.description
    }

    #expect(result.commandName == "createFaceKnife")
    #expect(result.didMutate)
    #expect(session.selectedTool == .select)
    #expect(session.selectedSceneNode?.reference == .body(faceKnifeFeatureID))
    #expect(session.polygonToolState.cutsFaces)
    #expect(faceKnifeFaces.count == 7)
    #expect(faceKnifeFaces.contains {
        $0.generatedRole == "faceKnife" && $0.subshapeRole == "centerFace"
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionPolygonKnifeUsesSelectedFacePlaneForSideFaces() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let sideFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "sideFace" &&
                abs($0.normal?.z ?? 1.0) < 0.5 &&
                $0.selectionTarget() != nil
        }
    )
    let sideFaceCenter = try #require(sideFaceEntry.center)
    let sideFaceNormal = try #require(sideFaceEntry.normal)
    let sideFaceTarget = try #require(sideFaceEntry.selectionTarget())

    #expect(session.selectTarget(sideFaceTarget))
    #expect(session.setPolygonSideCount(4))
    #expect(session.setPolygonCutsFaces(true))
    session.selectTool(.polygon)

    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.0, y: 0.0),
        endModelPoint: Point2D(x: 0.002, y: 0.0),
        sketchPlane: .xy
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .faceKnife(let faceKnife) = feature.operation else {
        Issue.record("Polygon Knife side-face drag should create a Face Knife feature.")
        return
    }
    let center = Point3D(x: sideFaceCenter.x, y: sideFaceCenter.y, z: sideFaceCenter.z)
    let normal = Vector3D(x: sideFaceNormal.x, y: sideFaceNormal.y, z: sideFaceNormal.z)
    let loopPlaneDistances = faceKnife.loop.map { point in
        abs((point - center).dot(normal))
    }

    #expect(result.commandName == "createFaceKnife")
    #expect(result.didMutate)
    #expect(loopPlaneDistances.allSatisfy { $0 < 1.0e-10 })
    #expect(faceKnife.loop.contains { abs($0.z - center.z) > 1.0e-4 })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionPolygonKnifeUsesSnappedTopologyWorldPointsOnSelectedFace() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let sideFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "sideFace" &&
                abs($0.normal?.z ?? 1.0) < 0.5 &&
                $0.selectionTarget() != nil
        }
    )
    let sideFaceCenter = try #require(sideFaceEntry.center)
    let sideFaceTarget = try #require(sideFaceEntry.selectionTarget())
    let sideFacePlane = try ConstructionPlaneTargetResolver().plane(
        alignedTo: sideFaceTarget,
        in: session.document,
        objectRegistry: .builtIn
    )
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sideFacePlane)
    let centerWorldPoint = Point3D(
        x: sideFaceCenter.x,
        y: sideFaceCenter.y,
        z: sideFaceCenter.z
    )
    let centerLocalPoint = coordinateSystem.project(centerWorldPoint).point
    let edgeWorldPoint = coordinateSystem.point(
        from: Point2D(
            x: centerLocalPoint.x + 0.002,
            y: centerLocalPoint.y
        )
    )

    #expect(session.selectTarget(sideFaceTarget))
    #expect(session.setPolygonSideCount(4))
    #expect(session.setPolygonCutsFaces(true))
    session.selectTool(.polygon)

    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.1, y: 0.1),
        endModelPoint: Point2D(x: 0.12, y: 0.1),
        sketchPlane: .xy,
        startWorldPoint: centerWorldPoint,
        endWorldPoint: edgeWorldPoint
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .faceKnife(let faceKnife) = feature.operation else {
        Issue.record("Polygon Knife should use snapped topology world points to create a Face Knife feature.")
        return
    }
    let average = faceKnife.loop.reduce(Point3D.origin) { partial, point in
        Point3D(
            x: partial.x + point.x / Double(faceKnife.loop.count),
            y: partial.y + point.y / Double(faceKnife.loop.count),
            z: partial.z + point.z / Double(faceKnife.loop.count)
        )
    }

    #expect(result.commandName == "createFaceKnife")
    #expect(result.didMutate)
    #expect(abs(average.x - centerWorldPoint.x) < 1.0e-10)
    #expect(abs(average.y - centerWorldPoint.y) < 1.0e-10)
    #expect(abs(average.z - centerWorldPoint.z) < 1.0e-10)
    #expect(faceKnife.loop.contains { abs($0.z - centerWorldPoint.z) > 1.0e-4 })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func editorSessionAppliesLengthInputToPolygonRadius() async throws {
    let session = EditorSession(selectedTool: .polygon)

    #expect(session.setSketchDimensionInputLength(0.018))
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.0, y: 0.0),
        endModelPoint: Point2D(x: 0.002, y: 0.0)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let node = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })

    #expect(result.didMutate)
    #expect(node.object?.properties["radius"] == .length(0.018))
    #expect(session.selectedTool == .select)
    #expect(session.sketchInputState.dimensionInputLengthMeters == nil)
}

@MainActor
@Test func editorSessionAppliesAngleInputToPolygonRotation() async throws {
    let session = EditorSession(selectedTool: .polygon)
    let angle = Double.pi / 6.0

    #expect(session.setSketchDimensionInputAngle(angle))
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.0, y: 0.0),
        endModelPoint: Point2D(x: 0.002, y: 0.0)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    let node = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas drag should create a polygon sketch feature.")
        return
    }
    let points = try resolvedLinePoints(
        in: sketch,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.didMutate)
    #expect(node.object?.properties["angle"] == .angle(30.0))
    #expect(points.contains { point in
        abs(point.x - cos(angle) * 0.002) < 1.0e-12
            && abs(point.y - sin(angle) * 0.002) < 1.0e-12
    })
    #expect(session.selectedTool == .select)
    #expect(session.sketchInputState.dimensionInputAngleRadians == nil)
}

@MainActor
@Test func editorSessionRejectsInvalidPolygonToolSideCount() async throws {
    let session = EditorSession()

    #expect(!session.setPolygonSideCount(2))
    #expect(session.polygonToolState.sideCount == PolygonToolState.defaultSideCount)
    #expect(session.diagnostics.last?.message == "Polygon side count must be between 3 and 256.")
}

@MainActor
@Test func editorSessionActivatesArcToolFromCanvasBackground() async throws {
    let session = EditorSession()

    session.selectTool(.arc)
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: -0.04, y: 0.025)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas click should create an arc sketch feature.")
        return
    }
    let arc = try #require(resolvedArc(in: sketch))
    let center = try resolvedPoint(
        arc.center,
        parameters: session.document.cadDocument.parameters
    )
    let radius = try resolvedLength(
        arc.radius,
        parameters: session.document.cadDocument.parameters
    )
    let startAngle = try resolvedAngle(
        arc.startAngle,
        parameters: session.document.cadDocument.parameters
    )
    let endAngle = try resolvedAngle(
        arc.endAngle,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createArcSketch")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    let draft = try CanvasSketchCurveDrafts.arc(
        centeredAt: Point2D(x: -0.04, y: 0.025)
    )
    #expect(center == draft.center)
    #expect(abs(radius - draft.radiusMeters) < 0.000_000_000_001)
    #expect(abs(startAngle - draft.startAngleRadians) < 0.000_000_000_001)
    #expect(abs(endAngle - draft.endAngleRadians) < 0.000_000_000_001)
}

@MainActor
@Test func editorSessionActivatesSplineToolFromCanvasBackground() async throws {
    let session = EditorSession()

    session.selectTool(.spline)
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: -0.04, y: 0.025)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas click should create a spline sketch feature.")
        return
    }
    let spline = try #require(resolvedSpline(in: sketch))
    let controlPoints = try spline.controlPoints.map { point in
        try resolvedPoint(
            point,
            parameters: session.document.cadDocument.parameters
        )
    }

    #expect(result.commandName == "createSplineSketch")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    let draft = try CanvasSketchCurveDrafts.spline(
        centeredAt: Point2D(x: -0.04, y: 0.025)
    )
    #expect(pointsMatch(controlPoints, draft.controlPoints))
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
@Test func editorSessionAppliesWidthAndHeightInputToRectangleDrag() async throws {
    let session = EditorSession(selectedTool: .sketch)

    #expect(session.setSketchDimensionInputWidth(0.05))
    #expect(session.setSketchDimensionInputHeight(0.02))
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
    #expect(points == Set([
        Point2D(x: -0.02, y: 0.02),
        Point2D(x: 0.03, y: 0.02),
        Point2D(x: 0.03, y: 0.04),
        Point2D(x: -0.02, y: 0.04),
    ]))
    #expect(session.selectedTool == .select)
    #expect(session.sketchInputState.dimensionInputWidthMeters == nil)
    #expect(session.sketchInputState.dimensionInputHeightMeters == nil)
}

@MainActor
@Test func editorSessionAppliesWidthAndHeightInputToRectangleClick() async throws {
    let session = EditorSession(selectedTool: .sketch)

    #expect(session.setSketchDimensionInputWidth(0.06))
    #expect(session.setSketchDimensionInputHeight(0.03))
    let result = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.01, y: -0.02)
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
    #expect(points == Set([
        Point2D(x: -0.02, y: -0.035),
        Point2D(x: 0.04, y: -0.035),
        Point2D(x: 0.04, y: -0.005),
        Point2D(x: -0.02, y: -0.005),
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
@Test func editorSessionAppliesLengthInputToCircleRadius() async throws {
    let session = EditorSession(selectedTool: .surface)

    #expect(session.setSketchDimensionInputLength(0.021))
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.01, y: -0.02),
        endModelPoint: Point2D(x: 0.012, y: -0.02)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas drag should create a sketch feature.")
        return
    }
    let circle = try #require(resolvedCircle(in: sketch))
    let radius = try resolvedLength(
        circle.radius,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createCircleSketch")
    #expect(result.didMutate)
    #expect(abs(radius - 0.021) < 1.0e-12)
    #expect(session.selectedTool == .select)
    #expect(session.sketchInputState.dimensionInputLengthMeters == nil)
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
@Test func editorSessionCreatesArcSketchFromCanvasDrag() async throws {
    let session = EditorSession()

    session.selectTool(.arc)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.01, y: -0.02),
        endModelPoint: Point2D(x: 0.04, y: 0.02)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas drag should create an arc sketch feature.")
        return
    }
    let arc = try #require(resolvedArc(in: sketch))
    let center = try resolvedPoint(
        arc.center,
        parameters: session.document.cadDocument.parameters
    )
    let radius = try resolvedLength(
        arc.radius,
        parameters: session.document.cadDocument.parameters
    )
    let startAngle = try resolvedAngle(
        arc.startAngle,
        parameters: session.document.cadDocument.parameters
    )
    let endAngle = try resolvedAngle(
        arc.endAngle,
        parameters: session.document.cadDocument.parameters
    )
    let draft = try CanvasSketchCurveDrafts.arc(
        fromCenter: Point2D(x: 0.01, y: -0.02),
        toRadiusPoint: Point2D(x: 0.04, y: 0.02)
    )

    #expect(result.commandName == "createArcSketch")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    #expect(sketch.entities.count == 1)
    #expect(center == draft.center)
    #expect(abs(radius - draft.radiusMeters) < 0.000_000_000_001)
    #expect(abs(startAngle - draft.startAngleRadians) < 0.000_000_000_001)
    #expect(abs(endAngle - draft.endAngleRadians) < 0.000_000_000_001)
}

@MainActor
@Test func editorSessionAppliesLengthInputToArcRadius() async throws {
    let session = EditorSession(selectedTool: .arc)

    #expect(session.setSketchDimensionInputLength(0.019))
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.01, y: -0.02),
        endModelPoint: Point2D(x: 0.012, y: -0.02)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas drag should create an arc sketch feature.")
        return
    }
    let arc = try #require(resolvedArc(in: sketch))
    let radius = try resolvedLength(
        arc.radius,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createArcSketch")
    #expect(result.didMutate)
    #expect(abs(radius - 0.019) < 1.0e-12)
    #expect(session.selectedTool == .select)
    #expect(session.sketchInputState.dimensionInputLengthMeters == nil)
}

@MainActor
@Test func editorSessionAppliesAngleInputToArcSpan() async throws {
    let session = EditorSession(selectedTool: .arc)
    let angle = Double.pi / 3.0

    #expect(session.setSketchDimensionInputAngle(angle))
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.01, y: -0.02),
        endModelPoint: Point2D(x: 0.04, y: 0.02)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas drag should create an arc sketch feature.")
        return
    }
    let arc = try #require(resolvedArc(in: sketch))
    let startAngle = try resolvedAngle(
        arc.startAngle,
        parameters: session.document.cadDocument.parameters
    )
    let endAngle = try resolvedAngle(
        arc.endAngle,
        parameters: session.document.cadDocument.parameters
    )

    #expect(result.commandName == "createArcSketch")
    #expect(result.didMutate)
    #expect(abs((endAngle - startAngle) - angle) < 1.0e-12)
    #expect(session.selectedTool == .select)
    #expect(session.sketchInputState.dimensionInputAngleRadians == nil)
}

@MainActor
@Test func editorSessionRejectsInvalidAngleInputForArcSpanBeforeMutation() async throws {
    let session = EditorSession(selectedTool: .arc)

    #expect(session.setSketchDimensionInputAngle(0.0))
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.01, y: -0.02),
        endModelPoint: Point2D(x: 0.04, y: 0.02)
    )

    #expect(!result.didMutate)
    #expect(result.revealsDiagnostics)
    #expect(session.selectedTool == .arc)
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.diagnostics.last?.message == "Canvas arc angle input must be greater than zero and less than a full circle.")
}

@MainActor
@Test func editorSessionRejectsDegenerateCanvasArcDrag() async throws {
    let session = EditorSession()

    session.selectTool(.arc)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 1.0, y: 1.0),
        endModelPoint: Point2D(x: 1.0, y: 1.0)
    )

    #expect(!result.didMutate)
    #expect(result.revealsDiagnostics)
    #expect(session.selectedTool == .arc)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.diagnostics.last?.message == "Canvas arc drag requires a non-zero radius.")
}

@MainActor
@Test func editorSessionCreatesSplineSketchFromCanvasDrag() async throws {
    let session = EditorSession()

    session.selectTool(.spline)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 0.0, y: 0.0),
        endModelPoint: Point2D(x: 0.03, y: 0.04)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        Issue.record("Canvas drag should create a spline sketch feature.")
        return
    }
    let spline = try #require(resolvedSpline(in: sketch))
    let controlPoints = try spline.controlPoints.map { point in
        try resolvedPoint(
            point,
            parameters: session.document.cadDocument.parameters
        )
    }

    #expect(result.commandName == "createSplineSketch")
    #expect(result.didMutate)
    #expect(result.selectedSceneNodeID != nil)
    #expect(session.selectedSceneNode?.reference == .sketch(featureID))
    #expect(session.selectedTool == .select)
    #expect(sketch.entities.count == 1)
    let draft = try CanvasSketchCurveDrafts.spline(
        from: Point2D(x: 0.0, y: 0.0),
        to: Point2D(x: 0.03, y: 0.04)
    )
    #expect(pointsMatch(controlPoints, draft.controlPoints))
}

@MainActor
@Test func editorSessionRejectsDegenerateCanvasSplineDrag() async throws {
    let session = EditorSession()

    session.selectTool(.spline)
    let result = session.activateSelectedToolFromCanvasDrag(
        startModelPoint: Point2D(x: 1.0, y: 1.0),
        endModelPoint: Point2D(x: 1.0, y: 1.0)
    )

    #expect(!result.didMutate)
    #expect(result.revealsDiagnostics)
    #expect(session.selectedTool == .spline)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
    #expect(session.diagnostics.last?.message == "Canvas spline drag requires distinct start and end coordinates.")
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
@Test func addSketchConstraintCommandSatisfiesHorizontalGeometry() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Constraint Horizontal Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
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
    let line = try #require(lineEntity(lineID, in: sketch))
    let start = try resolvedPoint(line.start, parameters: session.document.cadDocument.parameters)
    let end = try resolvedPoint(line.end, parameters: session.document.cadDocument.parameters)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(sketch.constraints == [.horizontal(lineID)])
    #expect(abs(start.x - 0.0) < 1.0e-12)
    #expect(abs(start.y - 0.0) < 1.0e-12)
    #expect(abs(end.x - 0.010) < 1.0e-12)
    #expect(abs(end.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandSatisfiesParallelGeometry() async throws {
    let setup = try twoLineConstraintCommandDocument(name: "Constraint Parallel Source")
    let session = EditorSession(document: setup.document)

    let result = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .parallel(setup.firstLineID, setup.secondLineID)
        )
    )

    let sketch = try #require(sketchFeature(in: session.document, featureID: setup.featureID))
    let follower = try #require(lineEntity(setup.secondLineID, in: sketch))
    let start = try resolvedPoint(follower.start, parameters: session.document.cadDocument.parameters)
    let end = try resolvedPoint(follower.end, parameters: session.document.cadDocument.parameters)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.constraints == [.parallel(setup.firstLineID, setup.secondLineID)])
    #expect(abs(start.x - 0.0) < 1.0e-12)
    #expect(abs(start.y - 0.005) < 1.0e-12)
    #expect(abs(end.x - 0.005) < 1.0e-12)
    #expect(abs(end.y - 0.005) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandSatisfiesCoincidentGeometry() async throws {
    let setup = try twoLineConstraintCommandDocument(name: "Constraint Coincident Source")
    let session = EditorSession(document: setup.document)

    let result = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .coincident(.lineEnd(setup.firstLineID), .lineStart(setup.secondLineID))
        )
    )

    let sketch = try #require(sketchFeature(in: session.document, featureID: setup.featureID))
    let first = try #require(lineEntity(setup.firstLineID, in: sketch))
    let second = try #require(lineEntity(setup.secondLineID, in: sketch))
    let firstEnd = try resolvedPoint(first.end, parameters: session.document.cadDocument.parameters)
    let secondStart = try resolvedPoint(second.start, parameters: session.document.cadDocument.parameters)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.constraints == [.coincident(.lineEnd(setup.firstLineID), .lineStart(setup.secondLineID))])
    #expect(abs(firstEnd.x - secondStart.x) < 1.0e-12)
    #expect(abs(firstEnd.y - secondStart.y) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandSatisfiesEqualLengthGeometry() async throws {
    let setup = try twoLineUnequalLengthConstraintCommandDocument(name: "Constraint Equal Length Source")
    let session = EditorSession(document: setup.document)

    let result = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .equalLength(setup.firstLineID, setup.secondLineID)
        )
    )

    let sketch = try #require(sketchFeature(in: session.document, featureID: setup.featureID))
    let first = try #require(lineEntity(setup.firstLineID, in: sketch))
    let second = try #require(lineEntity(setup.secondLineID, in: sketch))
    let firstLength = try lineLength(first, parameters: session.document.cadDocument.parameters)
    let secondLength = try lineLength(second, parameters: session.document.cadDocument.parameters)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.constraints == [.equalLength(setup.firstLineID, setup.secondLineID)])
    #expect(abs(firstLength - 0.005) < 1.0e-12)
    #expect(abs(secondLength - firstLength) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandSatisfiesTangentGeometry() async throws {
    let setup = try lineCircleTangentConstraintCommandDocument(name: "Constraint Tangent Source")
    let session = EditorSession(document: setup.document)

    let result = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .tangent(setup.lineID, setup.circleID)
        )
    )

    let sketch = try #require(sketchFeature(in: session.document, featureID: setup.featureID))
    let circle = try #require(circleEntity(setup.circleID, in: sketch))
    let center = try resolvedPoint(circle.center, parameters: session.document.cadDocument.parameters)
    let radius = try resolvedLength(circle.radius, parameters: session.document.cadDocument.parameters)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.constraints == [.tangent(setup.lineID, setup.circleID)])
    #expect(abs(center.x - 0.005) < 1.0e-12)
    #expect(abs(center.y - radius) < 1.0e-12)
    #expect(abs(radius - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandSatisfiesConcentricAndEqualRadiusGeometry() async throws {
    let setup = try twoCircleConstraintCommandDocument(name: "Constraint Circular Source")
    let session = EditorSession(document: setup.document)

    let concentricResult = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .concentric(setup.firstCircleID, setup.secondCircleID)
        )
    )
    let radiusResult = try session.execute(
        .addSketchConstraint(
            featureID: setup.featureID,
            constraint: .equalRadius(setup.firstCircleID, setup.secondCircleID)
        )
    )

    let sketch = try #require(sketchFeature(in: session.document, featureID: setup.featureID))
    let first = try #require(circleEntity(setup.firstCircleID, in: sketch))
    let second = try #require(circleEntity(setup.secondCircleID, in: sketch))
    let firstCenter = try resolvedPoint(first.center, parameters: session.document.cadDocument.parameters)
    let secondCenter = try resolvedPoint(second.center, parameters: session.document.cadDocument.parameters)
    let firstRadius = try resolvedLength(first.radius, parameters: session.document.cadDocument.parameters)
    let secondRadius = try resolvedLength(second.radius, parameters: session.document.cadDocument.parameters)
    #expect(concentricResult.commandName == "addSketchConstraint")
    #expect(radiusResult.commandName == "addSketchConstraint")
    #expect(concentricResult.didMutate)
    #expect(radiusResult.didMutate)
    #expect(sketch.constraints == [
        .concentric(setup.firstCircleID, setup.secondCircleID),
        .equalRadius(setup.firstCircleID, setup.secondCircleID),
    ])
    #expect(abs(firstCenter.x - secondCenter.x) < 1.0e-12)
    #expect(abs(firstCenter.y - secondCenter.y) < 1.0e-12)
    #expect(abs(firstRadius - secondRadius) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func addSketchConstraintCommandRejectsUnsatisfiableFixedLineAngle() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Fixed Constraint Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(singleSketchEntityID(in: session.document, featureID: featureID))
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineStart(lineID))
        )
    )
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(lineID))
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
    #expect(error?.message == "Sketch constraint cannot satisfy a fixed sketch line angle constraint.")
    #expect(session.generation == DocumentGeneration(3))
    #expect(sketch.constraints == [
        .fixed(.lineStart(lineID)),
        .fixed(.lineEnd(lineID)),
    ])
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
@Test func arcSketchCommandCreatesValidCurvePrimitive() async throws {
    let session = EditorSession()

    let result = try session.execute(
        .createArcSketch(
            name: "Trim Curve",
            plane: .xy,
            center: SketchPoint(
                x: .length(3.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            radius: .length(8.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        ),
        expectedGeneration: DocumentGeneration(0)
    )

    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .sketch(sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let entity = try #require(sketch.entities.values.first)
    guard case .arc(let arc) = entity else {
        #expect(Bool(false))
        return
    }
    let radius = try session.document.cadDocument.parameters.resolvedValue(for: arc.radius)
    let startAngle = try session.document.cadDocument.parameters.resolvedValue(for: arc.startAngle)
    let endAngle = try session.document.cadDocument.parameters.resolvedValue(for: arc.endAngle)
    let sceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first { node in
            node.object?.sourceFeatureID == featureID
        }
    )

    #expect(result.commandName == "createArcSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(feature.name == "Trim Curve")
    #expect(sketch.entities.count == 1)
    #expect(abs(radius.value - 0.008) <= 1.0e-12)
    #expect(radius.kind == .length)
    #expect(abs(startAngle.value - 0.0) <= 1.0e-12)
    #expect(abs(endAngle.value - Double.pi / 2.0) <= 1.0e-12)
    #expect(sceneNode.object?.typeID == .arc)
    #expect(sceneNode.object?.geometryRole == .curve)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@MainActor
@Test func arcSketchCommandRejectsFullCircleArc() async throws {
    let session = EditorSession()

    var caught: EditorError?
    do {
        _ = try session.execute(
            .createArcSketch(
                name: "Rejected Arc",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(8.0, .millimeter),
                startAngle: .angle(0.0, .degree),
                endAngle: .angle(360.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
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
@Test func extrudeProfileCommandUsesClosedSplineSketchReference() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Spline Profile",
            plane: .xy,
            spline: closedBezierCircleSpline(radius: 10.0, unit: .millimeter)
        )
    )
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)

    let result = try session.execute(
        .extrudeProfile(
            name: "Spline Body",
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .length(5.0, .millimeter),
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
@Test func extrudeProfileCommandRejectsOpenArcSketchBeforeMutation() async throws {
    var document = DesignDocument.empty()
    let sketchFeatureID = FeatureID()
    let firstLineID = SketchEntityID()
    let arcID = SketchEntityID()
    let secondLineID = SketchEntityID()
    let sketch = Sketch(
        plane: .xy,
        entities: [
            firstLineID: .line(SketchLine(
                start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                end: SketchPoint(x: .length(1.0, .meter), y: .length(0.0, .meter))
            )),
            arcID: .arc(SketchArc(
                center: SketchPoint(x: .length(1.0, .meter), y: .length(1.0, .meter)),
                radius: .length(1.0, .meter),
                startAngle: .angle(-Double.pi / 2.0, .radian),
                endAngle: .angle(0.0, .radian)
            )),
            secondLineID: .line(SketchLine(
                start: SketchPoint(x: .length(2.0, .meter), y: .length(1.0, .meter)),
                end: SketchPoint(x: .length(2.0, .meter), y: .length(2.0, .meter))
            )),
        ]
    )
    document.cadDocument.designGraph.nodes[sketchFeatureID] = FeatureNode(
        id: sketchFeatureID,
        name: "Open Arc Profile",
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    document.cadDocument.designGraph.order.append(sketchFeatureID)
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    let session = EditorSession(document: document)

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
    #expect(session.generation == DocumentGeneration(0))
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
@Test func rectangularPatternArrayCreatesSourceOwnedComponentInstancesThroughCommandPath() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let result = try session.execute(
        .createPatternArray(
            name: "Panel Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: Vector3D(x: 2.0, y: 0.0, z: 0.0),
                    distance: .length(30.0, .millimeter),
                    copyCount: 3,
                    distanceMode: .extent
                ),
                secondAxis: PatternArrayLinearAxis(
                    direction: .unitY,
                    distance: .length(20.0, .millimeter),
                    copyCount: 2,
                    distanceMode: .spacing
                )
            )),
            outputMode: .componentInstance
        )
    )

    let source = try #require(session.document.productMetadata.patternArrays.values.first)
    let groupNode = try #require(session.document.productMetadata.sceneNodes[source.rootSceneNodeID])
    let firstInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[0]]
    )
    let thirdInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[2]]
    )
    let fourthInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[3]]
    )

    #expect(result.commandName == "createPatternArray")
    #expect(result.generation == DocumentGeneration(3))
    #expect(source.name == "Panel Array")
    #expect(source.definitionID == definition.id)
    #expect(source.outputMode == .componentInstance)
    #expect(source.outputInstanceIDs.count == 11)
    #expect(groupNode.object?.category == .group)
    #expect(groupNode.childIDs.count == source.outputInstanceIDs.count)
    #expect(firstInstance.localTransform.matrix.values[12] == 0.01)
    #expect(firstInstance.localTransform.matrix.values[13] == 0.0)
    #expect(thirdInstance.localTransform.matrix.values[12] == 0.03)
    #expect(fourthInstance.localTransform.matrix.values[12] == 0.0)
    #expect(fourthInstance.localTransform.matrix.values[13] == 0.02)
    #expect(session.evaluationStatus == .valid)

    _ = try session.undo()
    #expect(session.document.productMetadata.patternArrays[source.id] == nil)
    #expect(session.document.productMetadata.componentInstances[source.outputInstanceIDs[0]] == nil)

    _ = try session.redo()
    #expect(session.document.productMetadata.patternArrays[source.id] != nil)
    #expect(session.document.productMetadata.componentInstances[source.outputInstanceIDs[0]] != nil)
}

@MainActor
@Test func patternArrayCommandCreatesRadialDistributionFromSource() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Radial Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let result = try session.execute(
        .createPatternArray(
            name: "Bolt Circle",
            definitionID: definition.id,
            distribution: .radial(
                RadialPatternArray(
                    angularAxis: PatternArrayAngularAxis(
                        center: .origin,
                        axis: .unitZ,
                        angle: .angle(90.0, .degree),
                        copyCount: 2,
                        angleMode: .spacing
                    ),
                    radialAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(5.0, .millimeter),
                        copyCount: 1,
                        distanceMode: .spacing
                    )
                )
            ),
            outputMode: .componentInstance
        )
    )

    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Bolt Circle"
    })
    let firstInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[0]]
    )
    let radialOnlyInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[2]]
    )
    let firstValues = firstInstance.localTransform.matrix.values
    let radialValues = radialOnlyInstance.localTransform.matrix.values

    #expect(result.commandName == "createPatternArray")
    #expect(result.didMutate)
    #expect(source.outputInstanceIDs.count == 5)
    #expect(commandStackApproximatelyEqual(firstValues[0], 0.0))
    #expect(commandStackApproximatelyEqual(firstValues[1], 1.0))
    #expect(commandStackApproximatelyEqual(firstValues[4], -1.0))
    #expect(commandStackApproximatelyEqual(firstValues[5], 0.0))
    #expect(commandStackApproximatelyEqual(radialValues[12], 0.005))
    #expect(commandStackApproximatelyEqual(radialValues[13], 0.0))
}

@MainActor
@Test func patternArrayCommandCreatesCurveDistributionFromPolylinePath() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Curve Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let result = try session.execute(
        .createPatternArray(
            name: "Curve Array",
            definitionID: definition.id,
            distribution: .curve(
                CurvePatternArray(
                    path: .polyline(
                        points: [
                            .origin,
                            Point3D(x: 0.03, y: 0.0, z: 0.0),
                        ],
                        normal: .unitZ
                    ),
                    copyCount: 3,
                    twist: .angle(90.0, .degree),
                    endScale: .scalar(2.0),
                    alignment: .parallel,
                    extent: .scalar(1.0),
                    extentMode: .ratio
                )
            ),
            outputMode: .componentInstance
        )
    )

    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Curve Array"
    })
    let firstInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[0]]
    )
    let thirdInstance = try #require(
        session.document.productMetadata.componentInstances[source.outputInstanceIDs[2]]
    )
    let firstValues = firstInstance.localTransform.matrix.values
    let thirdValues = thirdInstance.localTransform.matrix.values

    #expect(result.commandName == "createPatternArray")
    #expect(source.outputInstanceIDs.count == 3)
    #expect(commandStackApproximatelyEqual(firstValues[0], 4.0 / 3.0))
    #expect(commandStackApproximatelyEqual(firstValues[12], 0.01))
    #expect(commandStackApproximatelyEqual(thirdValues[0], 2.0))
    #expect(commandStackApproximatelyEqual(thirdValues[12], 0.03))
}

@MainActor
@Test func patternArrayCurveDistributionRegeneratesFromSketchEntityPathParameter() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try session.execute(
        .upsertParameter(
            name: "curveArrayPathLength",
            expression: .constant(.length(20.0, unit: .millimeter)),
            kind: .length
        )
    )
    let pathLength = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "curveArrayPathLength" }
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Curve Parameter Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Curve Parameter Source"
    })
    _ = try session.execute(
        .createLineSketch(
            name: "Curve Array Path",
            plane: .xy,
            start: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
            end: SketchPoint(x: .reference(pathLength.id), y: .length(0.0, .millimeter))
        )
    )
    let pathFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let pathFeature = try #require(session.document.cadDocument.designGraph.nodes[pathFeatureID])
    guard case let .sketch(pathSketch) = pathFeature.operation else {
        #expect(Bool(false))
        return
    }
    let pathEntityID = try #require(pathSketch.entities.first { _, entity in
        guard case .line = entity else {
            return false
        }
        return true
    }?.key)

    _ = try session.execute(
        .createPatternArray(
            name: "Sketch Path Curve Array",
            definitionID: definition.id,
            distribution: .curve(
                CurvePatternArray(
                    path: .sketchEntity(featureID: pathFeatureID, entityID: pathEntityID),
                    copyCount: 2,
                    alignment: .parallel
                )
            ),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Sketch Path Curve Array"
    })
    let outputIDs = source.outputInstanceIDs
    let initialFirst = try #require(session.document.productMetadata.componentInstances[outputIDs[0]])
    let initialSecond = try #require(session.document.productMetadata.componentInstances[outputIDs[1]])

    _ = try session.execute(
        .upsertParameter(
            name: "curveArrayPathLength",
            expression: .constant(.length(40.0, unit: .millimeter)),
            kind: .length
        )
    )

    let regeneratedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let regeneratedFirst = try #require(session.document.productMetadata.componentInstances[outputIDs[0]])
    let regeneratedSecond = try #require(session.document.productMetadata.componentInstances[outputIDs[1]])
    #expect(regeneratedSource.outputInstanceIDs == outputIDs)
    #expect(commandStackApproximatelyEqual(initialFirst.localTransform.matrix.values[12], 0.01))
    #expect(commandStackApproximatelyEqual(initialSecond.localTransform.matrix.values[12], 0.02))
    #expect(commandStackApproximatelyEqual(regeneratedFirst.localTransform.matrix.values[12], 0.02))
    #expect(commandStackApproximatelyEqual(regeneratedSecond.localTransform.matrix.values[12], 0.04))
}

@MainActor
@Test func patternArrayCurveDistributionUsesExactArcLengthForSketchArcPath() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Exact Arc Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Exact Arc Array Source"
    })
    _ = try session.execute(
        .createArcSketch(
            name: "Exact Arc Array Path",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
            radius: .length(20.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    let pathFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let pathFeature = try #require(session.document.cadDocument.designGraph.nodes[pathFeatureID])
    guard case let .sketch(pathSketch) = pathFeature.operation else {
        #expect(Bool(false))
        return
    }
    let pathEntityID = try #require(pathSketch.entities.first { _, entity in
        guard case .arc = entity else {
            return false
        }
        return true
    }?.key)

    _ = try session.execute(
        .createPatternArray(
            name: "Exact Arc Curve Array",
            definitionID: definition.id,
            distribution: .curve(
                CurvePatternArray(
                    path: .sketchEntity(featureID: pathFeatureID, entityID: pathEntityID),
                    copyCount: 2,
                    alignment: .parallel
                )
            ),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Exact Arc Curve Array"
    })
    let first = try #require(session.document.productMetadata.componentInstances[source.outputInstanceIDs[0]])
    let second = try #require(session.document.productMetadata.componentInstances[source.outputInstanceIDs[1]])
    let radius = 0.02
    let midpointCoordinate = radius / sqrt(2.0)

    #expect(commandStackApproximatelyEqual(first.localTransform.matrix.values[12], midpointCoordinate - radius))
    #expect(commandStackApproximatelyEqual(first.localTransform.matrix.values[13], midpointCoordinate))
    #expect(commandStackApproximatelyEqual(second.localTransform.matrix.values[12], -radius))
    #expect(commandStackApproximatelyEqual(second.localTransform.matrix.values[13], radius))
}

@MainActor
@Test func patternArrayCurveDistributionRejectsSubToleranceRatioExtentBeforeMutation() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Tiny Ratio Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Tiny Ratio Source"
    })
    let generation = session.generation
    let patternArrayCount = session.document.productMetadata.patternArrays.count

    var caught: EditorError?
    do {
        _ = try session.execute(
            .createPatternArray(
                name: "Tiny Ratio Curve Array",
                definitionID: definition.id,
                distribution: .curve(
                    CurvePatternArray(
                        path: .polyline(
                            points: [
                                .origin,
                                Point3D(x: 0.03, y: 0.0, z: 0.0),
                            ],
                            normal: .unitZ
                        ),
                        copyCount: 1,
                        alignment: .parallel,
                        extent: .scalar(1.0e-7),
                        extentMode: .ratio
                    )
                ),
                outputMode: .componentInstance
            )
        )
        Issue.record("Curve pattern array ratio extents must produce a meaningful path distance.")
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("positive path distance") == true)
    #expect(session.generation == generation)
    #expect(session.document.productMetadata.patternArrays.count == patternArrayCount)
}

@MainActor
@Test func rectangularPatternArrayRegeneratesOutputTransformsFromParameterSource() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try session.execute(
        .upsertParameter(
            name: "patternSpacing",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    let spacing = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "patternSpacing" }
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Regenerated Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Regenerated Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Regenerated Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .reference(spacing.id),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Regenerated Array"
    })
    let initialOutputIDs = source.outputInstanceIDs
    let initialFirstInstance = try #require(
        session.document.productMetadata.componentInstances[initialOutputIDs[0]]
    )

    _ = try session.execute(
        .upsertParameter(
            name: "patternSpacing",
            expression: .constant(.length(25.0, unit: .millimeter)),
            kind: .length
        )
    )

    let regeneratedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let regeneratedFirstInstance = try #require(
        session.document.productMetadata.componentInstances[initialOutputIDs[0]]
    )
    let regeneratedSecondInstance = try #require(
        session.document.productMetadata.componentInstances[initialOutputIDs[1]]
    )
    #expect(regeneratedSource.outputInstanceIDs == initialOutputIDs)
    #expect(initialFirstInstance.localTransform.matrix.values[12] == 0.01)
    #expect(regeneratedFirstInstance.localTransform.matrix.values[12] == 0.025)
    #expect(regeneratedSecondInstance.localTransform.matrix.values[12] == 0.05)
}

@MainActor
@Test func patternArrayCommandUpdatesSourceAndResynchronizesOutputs() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Update Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Update Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Editable Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 3
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Editable Array"
    })
    let initialOutputIDs = source.outputInstanceIDs
    let initialSecondOutputID = initialOutputIDs[1]

    let result = try session.execute(
        .updatePatternArray(
            id: source.id,
            name: "Updated Array",
            definitionID: nil,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(20.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: nil
        )
    )

    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let updatedGroupNode = try #require(session.document.productMetadata.sceneNodes[source.rootSceneNodeID])
    let reusedInstance = try #require(
        session.document.productMetadata.componentInstances[initialOutputIDs[0]]
    )

    #expect(result.commandName == "updatePatternArray")
    #expect(result.generation == DocumentGeneration(4))
    #expect(updatedSource.name == "Updated Array")
    #expect(updatedGroupNode.name == "Updated Array")
    #expect(updatedSource.outputInstanceIDs == [initialOutputIDs[0]])
    #expect(session.document.productMetadata.componentInstances[initialSecondOutputID] == nil)
    #expect(reusedInstance.localTransform.matrix.values[12] == 0.02)

    _ = try session.undo()
    let restoredSource = try #require(session.document.productMetadata.patternArrays[source.id])
    #expect(restoredSource.name == "Editable Array")
    #expect(restoredSource.outputInstanceIDs == initialOutputIDs)
    #expect(session.document.productMetadata.componentInstances[initialSecondOutputID] != nil)
}

@MainActor
@Test func patternArrayCommandExplodesSourceIntoIndependentFeatureCopies() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Explode Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Explode Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Explodable Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Explodable Array"
    })
    let outputInstanceID = try #require(source.outputInstanceIDs.first)
    let componentOutputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )
    let originalFeatureCount = session.document.cadDocument.designGraph.order.count

    let explodeResult = try session.execute(.explodePatternArray(id: source.id))
    let outputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )
    let clonedBodyFeatureID = try #require(
        commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: outputSceneNodeID,
            document: session.document
        )
    )
    let clonedFeature = try #require(session.document.cadDocument.designGraph.nodes[clonedBodyFeatureID])
    let originalFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case .extrude(let clonedExtrude) = clonedFeature.operation,
          case .extrude(let originalExtrude) = originalFeature.operation else {
        Issue.record("Pattern array explode should materialize cloned extrude feature copies.")
        return
    }

    #expect(explodeResult.commandName == "explodePatternArray")
    #expect(session.document.productMetadata.patternArrays[source.id] == nil)
    #expect(session.document.productMetadata.componentInstances[outputInstanceID] == nil)
    #expect(session.document.productMetadata.sceneNodes[componentOutputSceneNodeID] == nil)
    #expect(session.document.productMetadata.sceneNodes[outputSceneNodeID] != nil)
    #expect(session.document.cadDocument.designGraph.order.count == originalFeatureCount + 2)
    #expect(clonedBodyFeatureID != bodyFeatureID)
    #expect(clonedExtrude.profile.featureID != originalExtrude.profile.featureID)

    _ = try session.undo()
    #expect(session.document.productMetadata.patternArrays[source.id] != nil)
    #expect(session.document.cadDocument.designGraph.nodes[clonedBodyFeatureID] == nil)
    #expect(session.document.productMetadata.componentInstances[outputInstanceID] != nil)
    #expect(session.document.productMetadata.sceneNodes[componentOutputSceneNodeID] != nil)

    let independentTransform = try translationTransform(x: 0.03, y: 0.0, z: 0.0)
    do {
        _ = try session.execute(
            .setComponentInstanceTransform(
                id: outputInstanceID,
                localTransform: independentTransform
            )
        )
        Issue.record("Restored pattern array outputs must return to source-owned transforms.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
}

@MainActor
@Test func patternArrayIndependentCopyOutputClonesEditableFeatureGraph() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let originalFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case .extrude(let originalExtrude) = originalFeature.operation else {
        Issue.record("Default solid should be an extrude feature.")
        return
    }
    _ = try session.execute(
        .createComponentDefinition(
            name: "Independent Copy Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Independent Copy Source"
    })

    _ = try session.execute(
        .createPatternArray(
            name: "Independent Copy Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Independent Copy Array"
    })
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try #require(
        commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )
    let firstCloneFeature = try #require(session.document.cadDocument.designGraph.nodes[firstCloneBodyFeatureID])
    guard case .extrude(let firstCloneExtrude) = firstCloneFeature.operation else {
        Issue.record("Independent-copy pattern output should clone the source extrude.")
        return
    }

    #expect(source.outputMode == .independentCopy)
    #expect(source.outputInstanceIDs.isEmpty)
    #expect(source.outputSceneNodeIDs.count == 2)
    #expect(source.outputFeatureIDs.count == 4)
    #expect(!source.outputFeatureIDs.contains(bodyFeatureID))
    #expect(!source.outputFeatureIDs.contains(originalExtrude.profile.featureID))
    #expect(source.outputFeatureIDs.contains(firstCloneBodyFeatureID))
    #expect(source.outputFeatureIDs.contains(firstCloneExtrude.profile.featureID))
    #expect(firstCloneBodyFeatureID != bodyFeatureID)
    #expect(firstCloneExtrude.profile.featureID != originalExtrude.profile.featureID)

    let editedDistance = CADExpression.length(7.0, .millimeter)
    let editResult = try session.execute(
        .setExtrudeDistance(
            featureID: firstCloneBodyFeatureID,
            distance: editedDistance
        )
    )
    let editedCloneFeature = try #require(session.document.cadDocument.designGraph.nodes[firstCloneBodyFeatureID])
    let preservedOriginalFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case .extrude(let editedCloneExtrude) = editedCloneFeature.operation,
          case .extrude(let preservedOriginalExtrude) = preservedOriginalFeature.operation else {
        Issue.record("Independent-copy edit should keep both body features as extrudes.")
        return
    }

    #expect(editResult.commandName == "setExtrudeDistance")
    #expect(editedCloneExtrude.distance == editedDistance)
    #expect(preservedOriginalExtrude.distance == originalExtrude.distance)
}

@MainActor
@Test func independentPatternArrayRegenerationReusesEditedFeatureCopies() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Reusable Independent Copy Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Reusable Independent Copy Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Reusable Independent Copy Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Reusable Independent Copy Array"
    })
    let initialOutputSceneNodeIDs = source.outputSceneNodeIDs
    let firstOutputSceneNodeID = try #require(initialOutputSceneNodeIDs.first)
    let secondOutputSceneNodeID = try #require(initialOutputSceneNodeIDs.dropFirst().first)
    let firstCloneBodyFeatureID = try #require(
        commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )
    let editedDistance = CADExpression.length(7.0, .millimeter)
    _ = try session.execute(
        .setExtrudeDistance(
            featureID: firstCloneBodyFeatureID,
            distance: editedDistance
        )
    )

    _ = try session.execute(
        .updatePatternArray(
            id: source.id,
            name: nil,
            definitionID: nil,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(20.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: nil
        )
    )

    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let updatedFirstCloneFeature = try #require(
        session.document.cadDocument.designGraph.nodes[firstCloneBodyFeatureID]
    )
    guard case .extrude(let updatedExtrude) = updatedFirstCloneFeature.operation else {
        Issue.record("Reused independent-copy output should keep the edited extrude feature.")
        return
    }
    let secondOutputNode = try #require(
        session.document.productMetadata.sceneNodes[secondOutputSceneNodeID]
    )

    #expect(updatedSource.outputSceneNodeIDs == initialOutputSceneNodeIDs)
    #expect(updatedSource.outputFeatureIDs.contains(firstCloneBodyFeatureID))
    #expect(updatedExtrude.distance == editedDistance)
    #expect(secondOutputNode.localTransform.matrix.values[12] == 0.02)
}

@MainActor
@Test func independentPatternArrayRegenerationRemovesOnlyStaleTailOutputs() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Tail Reuse Independent Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Tail Reuse Independent Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Tail Reuse Independent Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Tail Reuse Independent Array"
    })
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let secondOutputSceneNodeID = try #require(source.outputSceneNodeIDs.dropFirst().first)
    let firstCloneBodyFeatureID = try #require(
        commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )
    let secondCloneBodyFeatureID = try #require(
        commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: secondOutputSceneNodeID,
            document: session.document
        )
    )
    let editedDistance = CADExpression.length(6.0, .millimeter)
    _ = try session.execute(
        .setExtrudeDistance(
            featureID: firstCloneBodyFeatureID,
            distance: editedDistance
        )
    )

    _ = try session.execute(
        .updatePatternArray(
            id: source.id,
            name: nil,
            definitionID: nil,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(12.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: nil
        )
    )

    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let updatedFirstCloneFeature = try #require(
        session.document.cadDocument.designGraph.nodes[firstCloneBodyFeatureID]
    )
    guard case .extrude(let updatedExtrude) = updatedFirstCloneFeature.operation else {
        Issue.record("Reused independent-copy output should keep the edited extrude feature.")
        return
    }

    #expect(updatedSource.outputSceneNodeIDs == [firstOutputSceneNodeID])
    #expect(updatedSource.outputFeatureIDs.contains(firstCloneBodyFeatureID))
    #expect(updatedExtrude.distance == editedDistance)
    #expect(session.document.productMetadata.sceneNodes[secondOutputSceneNodeID] == nil)
    #expect(session.document.cadDocument.designGraph.nodes[secondCloneBodyFeatureID] == nil)
}

@MainActor
@Test func componentDefinitionRejectsPatternArrayOutputSceneSubtree() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Pattern Source Definition",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Pattern Source Definition"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Definition Guard Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Definition Guard Array"
    })
    let outputRootSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let outputBodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[outputRootSceneNodeID]?.childIDs.first
    )
    let generation = session.generation

    do {
        _ = try session.execute(
            .createComponentDefinition(
                name: "Invalid Pattern Output Root",
                rootSceneNodeIDs: [outputRootSceneNodeID]
            )
        )
        Issue.record("Component definitions must reject pattern array output root scene nodes.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    do {
        _ = try session.execute(
            .createComponentDefinition(
                name: "Invalid Pattern Output Body",
                rootSceneNodeIDs: [outputBodySceneNodeID]
            )
        )
        Issue.record("Component definitions must reject pattern array output descendant scene nodes.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == generation)
    #expect(session.document.productMetadata.componentDefinitions.values.allSatisfy {
        $0.name != "Invalid Pattern Output Root" && $0.name != "Invalid Pattern Output Body"
    })
}

@MainActor
@Test func independentPatternArrayRegenerationRebuildsWhenDefinitionIdentityChanges() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let firstBodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let firstBodySceneNodeID = try #require(
        commandStackBodySceneNodeID(for: firstBodyFeatureID, in: session.document)
    )
    _ = try #require(
        session.createExtrudedRectangleFromCanvasClick(
            centerModelPoint: Point2D(x: 0.08, y: 0.0)
        )
    )
    let secondBodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let secondBodySceneNodeID = try #require(
        commandStackBodySceneNodeID(for: secondBodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Definition Identity Source",
            rootSceneNodeIDs: [firstBodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Definition Identity Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Definition Identity Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Definition Identity Array"
    })
    let initialDefinitionIdentity = try #require(source.definitionIdentity)
    let initialOutputSceneNodeIDs = source.outputSceneNodeIDs
    let initialOutputFeatureIDs = source.outputFeatureIDs
    let firstOutputSceneNodeID = try #require(initialOutputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try #require(
        commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )
    _ = try session.execute(
        .setExtrudeDistance(
            featureID: firstCloneBodyFeatureID,
            distance: .length(7.0, .millimeter)
        )
    )

    var metadata = session.document.productMetadata
    metadata.componentDefinitions[definition.id]?.rootSceneNodeIDs = [secondBodySceneNodeID]
    _ = try session.execute(.replaceProductMetadata(metadata))
    let staleSummary = PatternArraySummaryService().summarize(
        document: session.document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let staleCodes = Set(try #require(staleSummary.patternArrays.first).diagnostics.map(\.code))

    _ = try session.execute(
        .updatePatternArray(
            id: source.id,
            name: nil,
            definitionID: nil,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(12.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: nil
        )
    )

    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let updatedDefinitionIdentity = try #require(updatedSource.definitionIdentity)

    #expect(staleCodes.contains("independentCopyDefinitionIdentityMismatch"))
    #expect(updatedDefinitionIdentity != initialDefinitionIdentity)
    #expect(updatedSource.outputSceneNodeIDs != initialOutputSceneNodeIDs)
    #expect(updatedSource.outputFeatureIDs != initialOutputFeatureIDs)
    #expect(!updatedSource.outputFeatureIDs.contains(firstCloneBodyFeatureID))
    #expect(session.document.cadDocument.designGraph.nodes[firstCloneBodyFeatureID] == nil)
}

@MainActor
@Test func independentPatternArrayRegenerationRebuildsWhenSourceFeatureParametersChange() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let sourceBodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sourceBodySceneNodeID = try #require(
        commandStackBodySceneNodeID(for: sourceBodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Parameterized Identity Source",
            rootSceneNodeIDs: [sourceBodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Parameterized Identity Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Parameterized Identity Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Parameterized Identity Array"
    })
    let initialDefinitionIdentity = try #require(source.definitionIdentity)
    let initialOutputSceneNodeIDs = source.outputSceneNodeIDs
    let initialOutputFeatureIDs = source.outputFeatureIDs
    let firstOutputSceneNodeID = try #require(initialOutputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try #require(
        commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )

    _ = try session.execute(
        .setExtrudeDistance(
            featureID: sourceBodyFeatureID,
            distance: .length(9.0, .millimeter)
        )
    )
    let staleSummary = PatternArraySummaryService().summarize(
        document: session.document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let staleCodes = Set(try #require(staleSummary.patternArrays.first).diagnostics.map(\.code))

    _ = try session.execute(
        .updatePatternArray(
            id: source.id,
            name: nil,
            definitionID: nil,
            distribution: nil,
            outputMode: nil
        )
    )

    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let updatedDefinitionIdentity = try #require(updatedSource.definitionIdentity)

    #expect(staleCodes.contains("independentCopyDefinitionIdentityMismatch"))
    #expect(updatedDefinitionIdentity != initialDefinitionIdentity)
    #expect(updatedSource.outputSceneNodeIDs != initialOutputSceneNodeIDs)
    #expect(updatedSource.outputFeatureIDs != initialOutputFeatureIDs)
    #expect(!updatedSource.outputFeatureIDs.contains(firstCloneBodyFeatureID))
    #expect(session.document.cadDocument.designGraph.nodes[firstCloneBodyFeatureID] == nil)
}

@MainActor
@Test func independentPatternArrayUpdateRejectsRemovingOutputsWithExternalDependents() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let sourceBodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sourceBodySceneNodeID = try #require(
        commandStackBodySceneNodeID(for: sourceBodyFeatureID, in: session.document)
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Dependent Output Source",
            rootSceneNodeIDs: [sourceBodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Dependent Output Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Dependent Output Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Dependent Output Array"
    })
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try #require(
        commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: firstOutputSceneNodeID,
            document: session.document
        )
    )

    var document = session.document
    let dependentFeatureID = FeatureID()
    let dependentFeature = FeatureNode(
        id: dependentFeatureID,
        name: "Downstream Output Dependent",
        operation: .faceLoopOffset(FaceLoopOffsetFeature(
            target: FaceLoopOffsetTargetReference(featureID: firstCloneBodyFeatureID),
            facePersistentName: PersistentName(components: [
                .feature(firstCloneBodyFeatureID),
                .generated("extrude"),
                .subshape("startFace"),
            ]),
            distance: .length(1.0, .millimeter)
        )),
        inputs: [FeatureInput(featureID: firstCloneBodyFeatureID, role: .target)],
        outputs: [FeatureOutput(role: .body)]
    )
    try document.cadDocument.appendFeature(dependentFeature)
    let summary = PatternArraySummaryService().summarize(
        document: document,
        generation: session.generation,
        dirty: session.isDirty
    )
    let diagnosticCodes = Set(try #require(summary.patternArrays.first).diagnostics.map(\.code))

    do {
        try document.updatePatternArray(
            id: source.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 1
                )
            ))
        )
        Issue.record("Pattern array update should reject removing owned output features with external dependents.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("downstream features depend"))
    }

    #expect(diagnosticCodes.contains("independentCopyExternalFeatureDependents"))
    #expect(document.productMetadata.patternArrays[source.id]?.outputSceneNodeIDs == source.outputSceneNodeIDs)
    #expect(document.cadDocument.designGraph.nodes[firstCloneBodyFeatureID] != nil)
    #expect(document.cadDocument.designGraph.nodes[dependentFeatureID] != nil)
}

@MainActor
@Test func rectangularPatternArrayRejectsDeletingReferencedPatternParameterBeforeMutation() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try session.execute(
        .upsertParameter(
            name: "patternSpacing",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    let spacing = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "patternSpacing" }
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Parameter Guard Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Parameter Guard Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Parameter Guard Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .reference(spacing.id),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let generation = session.generation
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Parameter Guard Array"
    })
    let outputIDs = source.outputInstanceIDs

    do {
        _ = try session.execute(.deleteParameter(name: "patternSpacing"))
        Issue.record("Deleting a parameter referenced by a pattern source must be rejected.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == generation)
    #expect(session.document.cadDocument.parameters.parameters[spacing.id] != nil)
    #expect(session.document.productMetadata.patternArrays[source.id]?.outputInstanceIDs == outputIDs)
}

@MainActor
@Test func rectangularPatternArrayOwnsOutputTransforms() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Owned Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Owned Array Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Owned Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Owned Array"
    })
    let outputInstanceID = try #require(source.outputInstanceIDs.first)
    let outputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )

    do {
        _ = try session.execute(
            .setComponentInstanceTransform(
                id: outputInstanceID,
                localTransform: try translationTransform(x: 0.02, y: 0.0, z: 0.0)
            )
        )
        Issue.record("Pattern array output instance transforms must be controlled by the pattern source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    do {
        _ = try session.execute(
            .setSceneNodeTransform(
                id: outputSceneNodeID,
                localTransform: try translationTransform(x: 0.02, y: 0.0, z: 0.0)
            )
        )
        Issue.record("Pattern array output scene node transforms must be controlled by the pattern source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
}

@MainActor
@Test func productMetadataRejectsPatternArrayOutputInstanceOwnedByMultipleSources() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Exclusive Pattern Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Exclusive Pattern Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Exclusive Array A",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .componentInstance
        )
    )
    _ = try session.execute(
        .createPatternArray(
            name: "Exclusive Array B",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitY,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .componentInstance
        )
    )
    let sources = session.document.productMetadata.patternArrays.values.sorted { $0.name < $1.name }
    let firstSource = try #require(sources.first)
    var secondSource = try #require(sources.last)
    let firstOutputInstanceID = try #require(firstSource.outputInstanceIDs.first)
    var metadata = session.document.productMetadata
    secondSource.outputInstanceIDs = [firstOutputInstanceID]
    metadata.patternArrays[secondSource.id] = secondSource

    let result = try session.execute(.replaceProductMetadata(metadata))

    guard case .failed(let message) = session.evaluationStatus else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(message.contains("owned by exactly one pattern source"))
    #expect(session.diagnostics.first?.severity == .error)
}

@MainActor
@Test func productMetadataRejectsIndependentPatternArrayOutputSceneNodeOwnedByMultipleSources() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Exclusive Independent Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Exclusive Independent Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Exclusive Independent Array A",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    _ = try session.execute(
        .createPatternArray(
            name: "Exclusive Independent Array B",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitY,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    let sources = session.document.productMetadata.patternArrays.values.sorted { $0.name < $1.name }
    let firstSource = try #require(sources.first)
    var secondSource = try #require(sources.last)
    let firstOutputSceneNodeID = try #require(firstSource.outputSceneNodeIDs.first)
    var metadata = session.document.productMetadata
    secondSource.outputSceneNodeIDs = [firstOutputSceneNodeID]
    metadata.sceneNodes[secondSource.rootSceneNodeID]?.childIDs = [firstOutputSceneNodeID]
    metadata.patternArrays[secondSource.id] = secondSource

    let result = try session.execute(.replaceProductMetadata(metadata))

    guard case .failed(let message) = session.evaluationStatus else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(message.contains("output scene nodes must be owned by exactly one pattern source"))
    #expect(session.diagnostics.first?.severity == .error)
}

@MainActor
@Test func productMetadataRejectsIndependentPatternArrayOutputFeatureOwnedByMultipleSources() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Exclusive Independent Feature Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Exclusive Independent Feature Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Exclusive Independent Feature Array A",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    _ = try session.execute(
        .createPatternArray(
            name: "Exclusive Independent Feature Array B",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitY,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    let sources = session.document.productMetadata.patternArrays.values.sorted { $0.name < $1.name }
    let firstSource = try #require(sources.first)
    var secondSource = try #require(sources.last)
    var metadata = session.document.productMetadata
    secondSource.outputFeatureIDs = firstSource.outputFeatureIDs
    metadata.patternArrays[secondSource.id] = secondSource

    let result = try session.execute(.replaceProductMetadata(metadata))

    guard case .failed(let message) = session.evaluationStatus else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(message.contains("output features must be owned by exactly one pattern source"))
    #expect(session.diagnostics.first?.severity == .error)
}

@MainActor
@Test func rectangularPatternArrayOwnsGeneratedOutputMetadata() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Metadata Owned Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Metadata Owned Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Metadata Owned Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Metadata Owned Array"
    })
    let outputInstanceID = try #require(source.outputInstanceIDs.first)
    let outputSceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.childIDs.first
    )

    do {
        _ = try session.execute(.setComponentInstanceVisibility(id: outputInstanceID, isVisible: false))
        Issue.record("Pattern array output instance visibility must be controlled by the pattern source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    do {
        _ = try session.execute(.setComponentInstanceLock(id: outputInstanceID, isLocked: true))
        Issue.record("Pattern array output instance locks must be controlled by the pattern source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    do {
        _ = try session.execute(.setSceneNodeVisibility(id: outputSceneNodeID, isVisible: false))
        Issue.record("Pattern array output scene node visibility must be controlled by the pattern source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    do {
        _ = try session.execute(.setSceneNodeLock(id: outputSceneNodeID, isLocked: true))
        Issue.record("Pattern array output scene node locks must be controlled by the pattern source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
    do {
        _ = try session.execute(.setSceneNodeMaterial(id: outputSceneNodeID, materialID: nil))
        Issue.record("Pattern array output scene node materials must be controlled by the pattern source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    let sourceRootResult = try session.execute(
        .setSceneNodeVisibility(id: source.rootSceneNodeID, isVisible: false)
    )
    #expect(sourceRootResult.commandName == "setSceneNodeVisibility")
    #expect(session.document.productMetadata.sceneNodes[source.rootSceneNodeID]?.isVisible == false)
}

@MainActor
@Test func independentPatternArrayOwnsGeneratedOutputObjectProperties() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Property Owned Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Property Owned Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Property Owned Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Property Owned Array"
    })
    let outputRootSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let outputBodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes[outputRootSceneNodeID]?.childIDs.first
    )

    do {
        _ = try session.execute(
            .setSceneNodeObjectProperty(
                id: outputBodySceneNodeID,
                propertyID: ObjectPropertyID(rawValue: "generated.output.override"),
                value: .boolean(true)
            )
        )
        Issue.record("Independent-copy pattern array output object properties must be controlled by the source.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("Pattern array output"))
    }
}

@MainActor
@Test func independentPatternArrayMetadataRejectsForeignOwnedFeatures() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Foreign Feature Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Foreign Feature Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Foreign Feature Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Foreign Feature Array"
    })
    var metadata = session.document.productMetadata
    var invalidSource = try #require(metadata.patternArrays[source.id])
    invalidSource.outputFeatureIDs.append(bodyFeatureID)
    metadata.patternArrays[source.id] = invalidSource

    var validationError: DocumentValidationError?
    do {
        try metadata.validate(
            against: session.document.cadDocument,
            objectRegistry: .builtIn
        )
    } catch let error as DocumentValidationError {
        validationError = error
    }

    guard case .invalidProductMetadata(let message) = validationError else {
        #expect(Bool(false))
        return
    }
    #expect(message.contains("exactly match generated output dependencies"))
}

@MainActor
@Test func independentPatternArrayMetadataRejectsForeignObjectFeatureReferences() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyFeature = try #require(session.document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case .extrude(let extrude) = bodyFeature.operation else {
        Issue.record("Default body should be produced by an extrude.")
        return
    }
    let originalProfileFeatureID = extrude.profile.featureID
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Foreign Object Feature Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Foreign Object Feature Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Foreign Object Feature Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(10.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Foreign Object Feature Array"
    })
    #expect(!Set(source.outputFeatureIDs).contains(originalProfileFeatureID))

    var metadata = session.document.productMetadata
    let outputRootSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let outputBodySceneNodeID = try #require(metadata.sceneNodes[outputRootSceneNodeID]?.childIDs.first)
    var outputBodySceneNode = try #require(metadata.sceneNodes[outputBodySceneNodeID])
    var object = try #require(outputBodySceneNode.object)
    object.sourceSection = .profile(ProfileReference(featureID: originalProfileFeatureID))
    outputBodySceneNode.object = object
    metadata.sceneNodes[outputBodySceneNodeID] = outputBodySceneNode

    var validationError: DocumentValidationError?
    do {
        try metadata.validate(
            against: session.document.cadDocument,
            objectRegistry: .builtIn
        )
    } catch let error as DocumentValidationError {
        validationError = error
    }

    guard case .invalidProductMetadata(let message) = validationError else {
        #expect(Bool(false))
        return
    }
    #expect(message.contains("only owned cloned features"))
}

@MainActor
@Test func patternArrayMetadataValidationRequiresExactOutputGroup() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)
    _ = try session.execute(
        .createPatternArray(
            name: "Output Group Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(5.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )

    let source = try #require(session.document.productMetadata.patternArrays.values.first)
    var metadata = session.document.productMetadata
    var groupNode = try #require(metadata.sceneNodes[source.rootSceneNodeID])
    guard let removedChildID = groupNode.childIDs.popLast() else {
        #expect(Bool(false))
        return
    }
    metadata.sceneNodes[source.rootSceneNodeID] = groupNode
    metadata.sceneNodes.removeValue(forKey: removedChildID)

    var validationError: DocumentValidationError?
    do {
        try metadata.validate(
            against: session.document.cadDocument,
            objectRegistry: .builtIn
        )
    } catch let error as DocumentValidationError {
        validationError = error
    }

    guard case .invalidProductMetadata(let message) = validationError else {
        #expect(Bool(false))
        return
    }
    #expect(message.contains("exactly"))
}

@MainActor
@Test func patternArrayMetadataValidationRejectsStaleOutputTransforms() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Transform Guard Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)
    _ = try session.execute(
        .createPatternArray(
            name: "Transform Guard Array",
            definitionID: definition.id,
            distribution: .rectangular(
                RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(5.0, .millimeter),
                        copyCount: 2
                    )
                )
            ),
            outputMode: .componentInstance
        )
    )

    let source = try #require(session.document.productMetadata.patternArrays.values.first)
    let firstOutputID = try #require(source.outputInstanceIDs.first)
    var metadata = session.document.productMetadata
    metadata.componentInstances[firstOutputID]?.localTransform = .identity

    var validationError: DocumentValidationError?
    do {
        try metadata.validate(
            against: session.document.cadDocument,
            objectRegistry: .builtIn
        )
    } catch let error as DocumentValidationError {
        validationError = error
    }

    guard case .invalidProductMetadata(let message) = validationError else {
        #expect(Bool(false))
        return
    }
    #expect(message.contains("transforms"))
}

@MainActor
@Test func rectangularPatternArrayRejectsEmptyComponentDefinitionBeforeMutation() async throws {
    let session = EditorSession()
    _ = try session.execute(.createComponentDefinition(name: "Empty Array Source", rootSceneNodeIDs: []))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    var caught: EditorError?
    do {
        _ = try session.execute(
            .createPatternArray(
                name: "Empty Source Array",
                definitionID: definition.id,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(5.0, .millimeter),
                        copyCount: 2
                    )
                )),
                outputMode: .componentInstance
            )
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("renderable") == true)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.document.productMetadata.patternArrays.isEmpty)
    #expect(session.document.productMetadata.componentInstances.isEmpty)
}

@MainActor
@Test func rectangularPatternArrayRejectsInvalidInputsBeforeMutation() async throws {
    let session = EditorSession()

    var missingDefinitionError: EditorError?
    do {
        _ = try session.execute(
            .createPatternArray(
                name: "Missing Definition Array",
                definitionID: ComponentDefinitionID(),
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(10.0, .millimeter),
                        copyCount: 2
                    )
                )),
                outputMode: .componentInstance
            )
        )
    } catch let error as EditorError {
        missingDefinitionError = error
    }

    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(commandStackBodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(.createComponentDefinition(name: "Array Source", rootSceneNodeIDs: [bodySceneNodeID]))
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    var invalidAxisError: DocumentValidationError?
    do {
        _ = try session.execute(
            .createPatternArray(
                name: "Invalid Axis Array",
                definitionID: definition.id,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .zero,
                        distance: .length(10.0, .millimeter),
                        copyCount: 2
                    )
                )),
                outputMode: .componentInstance
            )
        )
    } catch let error as DocumentValidationError {
        invalidAxisError = error
    }

    var parallelAxisError: DocumentValidationError?
    do {
        _ = try session.execute(
            .createPatternArray(
                name: "Parallel Axis Array",
                definitionID: definition.id,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(10.0, .millimeter),
                        copyCount: 2
                    ),
                    secondAxis: PatternArrayLinearAxis(
                        direction: Vector3D(x: 2.0, y: 0.0, z: 0.0),
                        distance: .length(5.0, .millimeter),
                        copyCount: 2
                    )
                )),
                outputMode: .componentInstance
            )
        )
    } catch let error as DocumentValidationError {
        parallelAxisError = error
    }

    var budgetError: EditorError?
    do {
        _ = try session.execute(
            .createPatternArray(
                name: "Budget Array",
                definitionID: definition.id,
                distribution: .rectangular(RectangularPatternArray(
                    firstAxis: PatternArrayLinearAxis(
                        direction: .unitX,
                        distance: .length(1.0, .millimeter),
                        copyCount: 10_001
                    )
                )),
                outputMode: .componentInstance
            )
        )
    } catch let error as EditorError {
        budgetError = error
    }

    #expect(missingDefinitionError?.code == .referenceUnresolved)
    guard case .invalidProductMetadata(let message) = invalidAxisError else {
        #expect(Bool(false))
        return
    }
    #expect(message.contains("axis direction"))
    guard case .invalidProductMetadata(let parallelMessage) = parallelAxisError else {
        #expect(Bool(false))
        return
    }
    #expect(parallelMessage.contains("parallel"))
    #expect(budgetError?.code == .commandInvalid)
    #expect(budgetError?.message.contains("budget") == true)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.patternArrays.isEmpty)
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

private func linearDimensionMeters(
    _ kind: MeasurementResult.Solid.LinearDimension.Kind,
    in solid: MeasurementResult.Solid
) throws -> Double {
    let dimension = try #require(solid.linearDimensions.first { $0.kind == kind })
    return dimension.meters
}

private func lineEntity(
    _ entityID: SketchEntityID,
    in sketch: Sketch
) -> SketchLine? {
    guard let entity = sketch.entities[entityID],
          case .line(let line) = entity else {
        return nil
    }
    return line
}

private func circleEntity(
    _ entityID: SketchEntityID,
    in sketch: Sketch
) -> SketchCircle? {
    guard let entity = sketch.entities[entityID],
          case .circle(let circle) = entity else {
        return nil
    }
    return circle
}

private func twoLineConstraintCommandDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstLineID: SketchEntityID,
    secondLineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(0.005, .meter),
            y: .length(0.0, .meter)
        )
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Two line constraint setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: SketchPoint(
                x: .length(0.0, .meter),
                y: .length(0.005, .meter)
            ),
            end: SketchPoint(
                x: .length(0.0, .meter),
                y: .length(0.010, .meter)
            )
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

private func twoLineUnequalLengthConstraintCommandDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstLineID: SketchEntityID,
    secondLineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(0.005, .meter),
            y: .length(0.0, .meter)
        )
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Two line unequal length setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: SketchPoint(
                x: .length(0.0, .meter),
                y: .length(0.005, .meter)
            ),
            end: SketchPoint(
                x: .length(0.0, .meter),
                y: .length(0.015, .meter)
            )
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

private func lineCircleTangentConstraintCommandDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    circleID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: name,
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(0.010, .meter),
            y: .length(0.0, .meter)
        )
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Line circle tangent setup requires a line sketch."
        )
    }
    let circleID = SketchEntityID()
    sketch.entities[circleID] = .circle(
        SketchCircle(
            center: SketchPoint(
                x: .length(0.005, .meter),
                y: .length(0.006, .meter)
            ),
            radius: .length(0.002, .meter)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, circleID)
}

private func twoCircleConstraintCommandDocument(
    name: String
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstCircleID: SketchEntityID,
    secondCircleID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: name,
        plane: .xy,
        center: SketchPoint(
            x: .length(0.002, .meter),
            y: .length(0.003, .meter)
        ),
        radius: .length(0.004, .meter)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstCircleID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Two circle constraint setup requires a circle sketch."
        )
    }
    let secondCircleID = SketchEntityID()
    sketch.entities[secondCircleID] = .circle(
        SketchCircle(
            center: SketchPoint(
                x: .length(0.010, .meter),
                y: .length(0.011, .meter)
            ),
            radius: .length(0.001, .meter)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstCircleID, secondCircleID)
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

private func resolvedArc(in sketch: Sketch) -> SketchArc? {
    let arcs = sketch.entities.values.compactMap { entity in
        if case .arc(let arc) = entity {
            return arc
        }
        return nil
    }
    return arcs.count == 1 ? arcs[0] : nil
}

private func resolvedSpline(in sketch: Sketch) -> SketchSpline? {
    let splines = sketch.entities.values.compactMap { entity in
        if case .spline(let spline) = entity {
            return spline
        }
        return nil
    }
    return splines.count == 1 ? splines[0] : nil
}

private func pointsMatch(
    _ first: [Point2D],
    _ second: [Point2D],
    tolerance: Double = 1.0e-12
) -> Bool {
    guard first.count == second.count else {
        return false
    }
    return zip(first, second).allSatisfy { lhs, rhs in
        abs(lhs.x - rhs.x) <= tolerance
            && abs(lhs.y - rhs.y) <= tolerance
    }
}

private func closedBezierCircleSpline(
    radius: Double,
    unit: LengthUnit
) -> SketchSpline {
    let kappa = 0.552_284_749_830_793_6
    func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .length(x * radius, unit),
            y: .length(y * radius, unit)
        )
    }
    return SketchSpline(
        controlPoints: [
            point(1.0, 0.0),
            point(1.0, kappa),
            point(kappa, 1.0),
            point(0.0, 1.0),
            point(-kappa, 1.0),
            point(-1.0, kappa),
            point(-1.0, 0.0),
            point(-1.0, -kappa),
            point(-kappa, -1.0),
            point(0.0, -1.0),
            point(kappa, -1.0),
            point(1.0, -kappa),
            point(1.0, 0.0),
        ],
        isClosed: true
    )
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

private func resolvedAngle(
    _ expression: CADExpression,
    parameters: ParameterTable
) throws -> Double {
    let quantity = try parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .angle)
    return quantity.value
}

private func lineLength(
    _ line: SketchLine,
    parameters: ParameterTable
) throws -> Double {
    let start = try resolvedPoint(line.start, parameters: parameters)
    let end = try resolvedPoint(line.end, parameters: parameters)
    let deltaX = end.x - start.x
    let deltaY = end.y - start.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
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

private func commandStackBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private func commandStackBodyFeatureID(
    inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) -> FeatureID? {
    guard let sceneNode = document.productMetadata.sceneNodes[rootSceneNodeID] else {
        return nil
    }
    if sceneNode.reference?.kind == .body,
       let featureID = sceneNode.reference?.featureID {
        return featureID
    }
    for childID in sceneNode.childIDs {
        if let featureID = commandStackBodyFeatureID(
            inSceneSubtreeRootedAt: childID,
            document: document
        ) {
            return featureID
        }
    }
    return nil
}

private func commandStackTopologyPoint(
    _ point: TopologySummaryResult.Entry.Point?,
    isOnDepth depth: Double
) -> Bool {
    guard let point else {
        return false
    }
    return abs(point.z - depth) < 1.0e-10
}

private func commandStackApproximatelyEqual(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-10
) -> Bool {
    abs(lhs - rhs) <= tolerance
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
