import AppKit
import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

private let viewportSceneSnapshotTestDocumentID = DocumentID()

@Test func viewportSceneSnapshotCacheReusesMatchingKey() {
    let cache = ViewportSceneSnapshotCache()
    let key = viewportSceneSnapshotTestKey(generation: 1)
    var buildCount = 0

    _ = cache.scene(for: key) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: key) {
        buildCount += 1
        return ViewportScene(items: [])
    }

    #expect(buildCount == 1)
}

@Test func viewportSceneSnapshotCacheRebuildsWhenKeyChanges() {
    let cache = ViewportSceneSnapshotCache()
    var buildCount = 0

    _ = cache.scene(for: viewportSceneSnapshotTestKey(generation: 1)) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: viewportSceneSnapshotTestKey(generation: 2)) {
        buildCount += 1
        return ViewportScene(items: [])
    }

    #expect(buildCount == 2)
}

@Test func viewportSceneSnapshotCacheSeparatesPresentationSourceRevisions() {
    let cache = ViewportSceneSnapshotCache()
    let projectID = ProjectID(rawValue: "project.scene-key-preview")
    let first = EvaluationSnapshotID(projectID: projectID, purpose: .presentation, sourceRevision: DocumentTransactionRevision(1))
    let second = EvaluationSnapshotID(projectID: projectID, purpose: .presentation, sourceRevision: DocumentTransactionRevision(2))
    var buildCount = 0
    for snapshot in [first, second, first] {
        _ = cache.scene(for: viewportSceneSnapshotTestKey(source: .presentation(snapshot))) {
            buildCount += 1
            return ViewportScene(items: [])
        }
    }
    #expect(buildCount == 2)
}

@Test func viewportSceneSnapshotCacheRebuildsWhenWorkspaceRevisionChanges() {
    let cache = ViewportSceneSnapshotCache()
    let source = ViewportSceneSnapshotKey.Source.document(
        id: viewportSceneSnapshotTestDocumentID,
        generation: DocumentGeneration(1)
    )
    let initialState = ViewportWorkspaceRenderState(
        revision: WorkspaceRevision(0),
        ruler: .standard(for: .millimeter)
    )
    let updatedState = ViewportWorkspaceRenderState(
        revision: WorkspaceRevision(1),
        ruler: .standard(for: .millimeter)
    )
    var buildCount = 0

    _ = cache.scene(for: viewportSceneSnapshotTestKey(
        source: source,
        workspaceRenderState: initialState
    )) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: viewportSceneSnapshotTestKey(
        source: source,
        workspaceRenderState: updatedState
    )) {
        buildCount += 1
        return ViewportScene(items: [])
    }

    #expect(buildCount == 2)
}

@Test func viewportSceneSnapshotCacheKeysExactWorkspaceRenderInputs() {
    let cache = ViewportSceneSnapshotCache()
    let source = ViewportSceneSnapshotKey.Source.document(
        id: viewportSceneSnapshotTestDocumentID,
        generation: DocumentGeneration(1)
    )
    let componentID = SelectionComponentID.sketchEntity(
        featureID: FeatureID(),
        entityID: SketchEntityID()
    )
    let baseState = ViewportWorkspaceRenderState(
        revision: WorkspaceRevision(0),
        ruler: .standard(for: .millimeter)
    )
    let rulerState = ViewportWorkspaceRenderState(
        revision: WorkspaceRevision(0),
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )
    let overlayState = ViewportWorkspaceRenderState(
        revision: WorkspaceRevision(0),
        ruler: .standard(for: .millimeter),
        sceneOverlayState: ViewportSceneOverlayState(
            pointDisplays: [
                componentID: PointDisplay(componentID: componentID, isVisible: true),
            ]
        )
    )
    var buildCount = 0

    for workspaceRenderState in [baseState, rulerState, overlayState] {
        _ = cache.scene(for: viewportSceneSnapshotTestKey(
            source: source,
            workspaceRenderState: workspaceRenderState
        )) {
            buildCount += 1
            return ViewportScene(items: [])
        }
    }

    #expect(buildCount == 3)
}

@Test func viewportSceneSnapshotCacheRetainsMultipleRecentKeys() {
    let cache = ViewportSceneSnapshotCache()
    let documentKey = viewportSceneSnapshotTestKey(source: .document(
        id: viewportSceneSnapshotTestDocumentID,
        generation: DocumentGeneration(1)
    ))
    let previewKey = viewportSceneSnapshotTestKey(source: .dragPreview(
        documentID: viewportSceneSnapshotTestDocumentID,
        revision: 1
    ))
    var buildCount = 0

    _ = cache.scene(for: documentKey) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: previewKey) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: documentKey) {
        buildCount += 1
        return ViewportScene(items: [])
    }

    #expect(buildCount == 2)
}

@Test func viewportSceneSnapshotCacheSeparatesDocumentsAtMatchingGenerations() {
    let cache = ViewportSceneSnapshotCache()
    let firstSource = ViewportSceneSnapshotKey.Source.document(
        id: DocumentID(),
        generation: DocumentGeneration(1)
    )
    let secondSource = ViewportSceneSnapshotKey.Source.document(
        id: DocumentID(),
        generation: DocumentGeneration(1)
    )
    var buildCount = 0

    _ = cache.scene(for: viewportSceneSnapshotTestKey(source: firstSource)) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: viewportSceneSnapshotTestKey(source: secondSource)) {
        buildCount += 1
        return ViewportScene(items: [])
    }

    #expect(buildCount == 2)
}

@Test func viewportSceneSnapshotCacheEvictsLeastRecentKeyWhenCapacityIsExceeded() {
    let cache = ViewportSceneSnapshotCache(maximumEntryCount: 1)
    let firstKey = viewportSceneSnapshotTestKey(generation: 1)
    let secondKey = viewportSceneSnapshotTestKey(generation: 2)
    var buildCount = 0

    _ = cache.scene(for: firstKey) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: secondKey) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: firstKey) {
        buildCount += 1
        return ViewportScene(items: [])
    }

    #expect(buildCount == 3)
}

@Test func viewportSceneSnapshotCacheDoesNotReuseMissingKey() {
    let cache = ViewportSceneSnapshotCache()
    var buildCount = 0

    _ = cache.scene(for: nil) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    _ = cache.scene(for: nil) {
        buildCount += 1
        return ViewportScene(items: [])
    }

    #expect(buildCount == 2)
}

@Test func viewportSceneSnapshotCacheInvalidationDropsCachedScene() {
    let cache = ViewportSceneSnapshotCache()
    let key = viewportSceneSnapshotTestKey(generation: 1)
    var buildCount = 0

    _ = cache.scene(for: key) {
        buildCount += 1
        return ViewportScene(items: [])
    }
    cache.invalidate()
    _ = cache.scene(for: key) {
        buildCount += 1
        return ViewportScene(items: [])
    }

    #expect(buildCount == 2)
}

private func viewportSceneSnapshotTestKey(generation: UInt64) -> ViewportSceneSnapshotKey {
    viewportSceneSnapshotTestKey(source: .document(
        id: viewportSceneSnapshotTestDocumentID,
        generation: DocumentGeneration(generation)
    ))
}

private func viewportSceneSnapshotTestKey(
    source: ViewportSceneSnapshotKey.Source,
    workspaceRenderState: ViewportWorkspaceRenderState = ViewportWorkspaceRenderState(
        revision: WorkspaceRevision(),
        ruler: .standard(for: .millimeter)
    )
) -> ViewportSceneSnapshotKey {
    ViewportSceneSnapshotKey(
        source: source,
        currentEvaluationGeneration: nil,
        evaluationCacheGeneration: nil,
        workspaceRenderState: workspaceRenderState,
        renderInvalidation: RenderInvalidation(),
        sectionClippingPlan: nil,
        objectDefinitions: []
    )
}

@MainActor
@Test func viewportSceneBuilderCreatesSelectableSketchAndBodyItems() async throws {
    let session = EditorSession()
    let sketchResult = try session.execute(
        .createRectangleSketch(
            name: "Selectable Sketch",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter)
        )
    )
    let sketchFeatureID = try #require(sketchResult.primaryFeatureID)
    _ = try session.execute(
        .extrudeProfile(
            name: "Selectable Body",
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .length(5.0, .millimeter),
            direction: .normal
        )
    )

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)

    #expect(scene.items.count == 2)
    #expect(scene.items.contains { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    #expect(scene.items.contains { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    #expect(scene.items.contains { item in
        if case .body(let component) = item.kind {
            return component.bodyID?.isEmpty == false
        }
        return false
    })
    #expect(scene.modelBounds != nil)
}

@MainActor
@Test func viewportSceneBuilderHidesConsumedProfileSketchOfPlacedPrimitive() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)

    // A placed primitive reads as one object: its consumed profile sketch is
    // nested under the body and hidden, so only the body item is built.
    #expect(scene.items.count == 1)
    #expect(scene.items.contains { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    #expect(scene.items.contains { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    } == false)
    #expect(scene.modelBounds != nil)
}

@MainActor
@Test func viewportSceneBuilderUsesRulerScaledMinimumSketchBounds() throws {
    var document = DesignDocument.empty()
    let ruler = WorkspaceScalePreset.microFabrication.rulerConfiguration
    let featureID = try document.createLineSketch(
        name: "Micro Vertical Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(2.0e-6, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(2.0e-6, .meter),
            y: .length(3.0e-6, .meter)
        )
    )

    let scene = ViewportSceneBuilder().build(document: document, ruler: ruler)
    let item = try #require(scene.items.first { $0.featureID == featureID })

    #expect(abs(item.modelBounds.width - 1.0e-6) < 1.0e-18)
    #expect(abs(item.modelBounds.height - 3.0e-6) < 1.0e-18)
    #expect(abs(item.modelBounds.midX - 2.0e-6) < 1.0e-18)
    #expect(abs(item.modelBounds.midY - 1.5e-6) < 1.0e-18)
    #expect(item.modelBounds.width < 0.001)
}

@MainActor
@Test func viewportSceneBuilderExpandsComponentInstancePatternItemsWithSceneNodeIdentity() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Viewport Pattern Source",
            rootSceneNodeIDs: [bodyNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Viewport Pattern Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Viewport Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(100.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first)

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let baseBody = try #require(scene.items.first { item in
        item.componentInstanceID == nil && item.featureID == bodyFeatureID
    })
    let instanceItems = scene.items
        .filter { $0.componentInstanceID != nil && $0.featureID == bodyFeatureID }
        .sorted { $0.modelBounds.midX < $1.modelBounds.midX }

    #expect(instanceItems.count == 2)
    #expect(Set(instanceItems.compactMap(\.componentInstanceID)) == Set(source.outputInstanceIDs))
    #expect(abs(instanceItems[0].modelTransform.matrix.values[3] - 0.1) < 1.0e-12)
    #expect(abs(instanceItems[1].modelTransform.matrix.values[3] - 0.2) < 1.0e-12)
    #expect(abs(instanceItems[0].modelBounds.midX - (baseBody.modelBounds.midX + 0.1)) < 1.0e-12)
    #expect(abs(instanceItems[1].modelBounds.midX - (baseBody.modelBounds.midX + 0.2)) < 1.0e-12)

    _ = try session.execute(.setSceneNodeVisibility(id: source.rootSceneNodeID, isVisible: false))
    let hiddenScene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    #expect(hiddenScene.items.contains { $0.componentInstanceID != nil } == false)
}

@MainActor
@Test func viewportSceneBuilderAppliesDocumentRootTransformToComponentInstanceItems() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Transformed Component Source",
            rootSceneNodeIDs: [bodyNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Transformed Component Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Transformed Component Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(100.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Transformed Component Pattern"
    })
    let documentRootSceneNodeID = try #require(session.document.productMetadata.rootSceneNodeIDs.first)
    _ = try session.execute(
        .setSceneNodeTransform(
            id: documentRootSceneNodeID,
            localTransform: translationTransform(x: 0.03, y: 0.0, z: 0.0)
        )
    )
    let outputInstanceID = try #require(source.outputInstanceIDs.first)

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let baseBody = try #require(scene.items.first { item in
        item.componentInstanceID == nil && item.featureID == bodyFeatureID
    })
    let instanceBody = try #require(scene.items.first { item in
        item.componentInstanceID == outputInstanceID && item.featureID == bodyFeatureID
    })

    #expect(abs(instanceBody.modelTransform.matrix.values[3] - 0.13) < 1.0e-12)
    #expect(abs(instanceBody.modelBounds.midX - (baseBody.modelBounds.midX + 0.1)) < 1.0e-12)
}

@MainActor
@Test func viewportSceneBuilderAppliesIndependentCopyOutputSceneTransforms() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Independent Copy Viewport Source",
            rootSceneNodeIDs: [bodyNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Independent Copy Viewport Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Independent Copy Viewport Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(100.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Independent Copy Viewport Pattern"
    })
    let outputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let outputSubtreeIDs = Set(sceneSubtreeIDs(rootedAt: outputSceneNodeID, document: session.document))

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let baseBody = try #require(scene.items.first { item in
        item.sceneNodeID == bodyNodeID && item.featureID == bodyFeatureID
    })
    let outputBody = try #require(scene.items.first { item in
        guard let sceneNodeID = item.sceneNodeID else {
            return false
        }
        return outputSubtreeIDs.contains(sceneNodeID) && source.outputFeatureIDs.contains(item.featureID)
    })

    #expect(abs(outputBody.modelTransform.matrix.values[3] - 0.1) < 1.0e-12)
    #expect(abs(outputBody.modelBounds.midX - (baseBody.modelBounds.midX + 0.1)) < 1.0e-12)
}

@MainActor
@Test func viewportSceneBuilderExpandsNestedComponentInstancePatternDefinitions() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(bodySceneNodeID(for: bodyFeatureID, in: session.document))
    _ = try session.execute(
        .createComponentDefinition(
            name: "Nested Body Definition",
            rootSceneNodeIDs: [bodyNodeID]
        )
    )
    let bodyDefinition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Nested Body Definition"
    })
    _ = try session.execute(
        .createComponentInstance(
            name: "Nested Source Instance",
            definitionID: bodyDefinition.id,
            localTransform: .identity
        )
    )
    let sourceInstance = try #require(session.document.productMetadata.componentInstances.values.first {
        $0.name == "Nested Source Instance"
    })
    let sourceInstanceNodeID = try #require(session.document.productMetadata.sceneNodes.first { _, node in
        node.reference?.componentInstanceID == sourceInstance.id
    }?.key)
    _ = try session.execute(
        .createComponentDefinition(
            name: "Nested Pattern Definition",
            rootSceneNodeIDs: [sourceInstanceNodeID]
        )
    )
    let nestedDefinition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Nested Pattern Definition"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Nested Pattern",
            definitionID: nestedDefinition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(50.0, .millimeter),
                    copyCount: 1
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Nested Pattern"
    })
    let outputInstanceID = try #require(source.outputInstanceIDs.first)

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let outputItems = scene.items.filter {
        $0.componentInstanceID == outputInstanceID && $0.featureID == bodyFeatureID
    }

    #expect(outputItems.count == 1)
    #expect(abs((outputItems.first?.modelTransform.matrix.values[3] ?? 0.0) - 0.05) < 1.0e-12)
}

@MainActor
@Test func viewportSceneBuilderUsesCurrentEvaluatedDocumentWhenAvailable() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluationCache = try #require(session.currentEvaluationCache)

    let documentScene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let cachedScene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: session.workspaceState.ruler,
        documentGeneration: session.generation,
        evaluationCache: evaluationCache
    )

    #expect(viewportSceneIgnoringEvaluationLocalBodyIDs(cachedScene) == viewportSceneIgnoringEvaluationLocalBodyIDs(documentScene))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderEvaluatesAndDisplaysKernelProjectedCurveWithoutCache() async throws {
    var document = DesignDocument.empty()
    let sourceFeatureID = try document.createLineSketch(
        name: "Viewport projection source",
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
    let projectedFeatureID = try document.createProjectedCurve(
        name: "Viewport projected curve",
        source: CurveOutputReference(featureID: sourceFeatureID),
        planeOrigin: Point3D(x: 0.0, y: 0.0, z: 0.005),
        planeNormal: .unitZ
    )
    let session = EditorSession(document: document)
    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: session.workspaceState.ruler
    )
    let item = try #require(scene.items.first { $0.featureID == projectedFeatureID })
    guard case let .curve(component) = item.kind else {
        Issue.record("Projected curve must produce a viewport curve item.")
        return
    }
    let segment = try #require(component.segments.first)
    let points = segment.points
    let expectedReference = CurveOutputReference(featureID: projectedFeatureID, curveIndex: 0)
    #expect(segment.reference == expectedReference)
    #expect(segment.curve.exactCurve != nil)
    #expect(points.count >= 2)
    #expect(points.allSatisfy { abs($0.z - 0.005) <= 1.0e-12 })
    #expect(item.sceneNodeID != nil)
}

@MainActor
@Test func viewportSceneBuilderUsesCurrentEvaluationContextWhenAvailable() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(session.currentEvaluation)

    let documentScene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let contextScene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: session.workspaceState.ruler,
        currentEvaluation: currentEvaluation,
        documentGeneration: session.generation
    )

    #expect(viewportSceneIgnoringEvaluationLocalBodyIDs(contextScene) == viewportSceneIgnoringEvaluationLocalBodyIDs(documentScene))
}

@MainActor
@Test func viewportSceneBuilderIgnoresCurrentEvaluationWhenGenerationIsStale() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(session.currentEvaluation)

    let documentScene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let staleScene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: session.workspaceState.ruler,
        currentEvaluation: currentEvaluation,
        documentGeneration: DocumentGeneration(session.generation.value + 1)
    )

    #expect(viewportSceneIgnoringEvaluationLocalBodyIDs(staleScene) == viewportSceneIgnoringEvaluationLocalBodyIDs(documentScene))
}

@MainActor
@Test func viewportSceneBuilderIgnoresCurrentEvaluationWhenSourceFingerprintDiffers() async throws {
    let rectangleSession = EditorSession()
    _ = try #require(rectangleSession.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(rectangleSession.currentEvaluation)

    let circleSession = EditorSession()
    _ = try #require(circleSession.createDefaultExtrudedCircle())

    let circleScene = ViewportSceneBuilder().build(document: circleSession.document, ruler: circleSession.workspaceState.ruler)
    let mismatchedScene = ViewportSceneBuilder().build(
        document: circleSession.document,
        ruler: circleSession.workspaceState.ruler,
        currentEvaluation: currentEvaluation,
        documentGeneration: rectangleSession.generation
    )

    #expect(viewportSceneIgnoringEvaluationLocalBodyIDs(mismatchedScene) == viewportSceneIgnoringEvaluationLocalBodyIDs(circleScene))
}

@MainActor
@Test func viewportSceneBuilderIgnoresEvaluationCacheWhenGenerationIsStale() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluationCache = try #require(session.currentEvaluationCache)

    let documentScene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let staleScene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: session.workspaceState.ruler,
        documentGeneration: DocumentGeneration(session.generation.value + 1),
        evaluationCache: evaluationCache
    )

    #expect(viewportSceneIgnoringEvaluationLocalBodyIDs(staleScene) == viewportSceneIgnoringEvaluationLocalBodyIDs(documentScene))
}

@MainActor
@Test func viewportSceneBuilderIgnoresEvaluationCacheWhenSourceFingerprintDiffers() async throws {
    let rectangleSession = EditorSession()
    _ = try #require(rectangleSession.createDefaultExtrudedRectangle())
    let rectangleCache = try #require(rectangleSession.currentEvaluationCache)

    let circleSession = EditorSession()
    _ = try #require(circleSession.createDefaultExtrudedCircle())

    let circleScene = ViewportSceneBuilder().build(document: circleSession.document, ruler: circleSession.workspaceState.ruler)
    let mismatchedScene = ViewportSceneBuilder().build(
        document: circleSession.document,
        ruler: circleSession.workspaceState.ruler,
        documentGeneration: rectangleCache.generation,
        evaluationCache: rectangleCache
    )

    #expect(viewportSceneIgnoringEvaluationLocalBodyIDs(mismatchedScene) == viewportSceneIgnoringEvaluationLocalBodyIDs(circleScene))
}

@Test func viewportFaceSurfacePointResolverRestoresPointInsideProjectedFace() throws {
    let componentID = SelectionComponentID.generatedTopology(generatedTopologyTestSubshapeID("feature:body:subshape:test:face:front"))
    let face = ViewportBodyTopology.Face(
        componentID: componentID,
        points: [
            Point3D(x: -0.010, y: 0.0, z: -0.010),
            Point3D(x: 0.010, y: 0.0, z: -0.010),
            Point3D(x: 0.010, y: 0.0, z: 0.010),
            Point3D(x: -0.010, y: 0.0, z: 0.010),
        ]
    )
    let expected = Point3D(x: 0.003, y: 0.0, z: 0.004)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.02, y: -0.02, width: 0.04, height: 0.04),
        size: CGSize(width: 640.0, height: 480.0)
    )
    let viewportPoint = layout.project(expected)

    let resolved = try #require(
        ViewportFaceSurfacePointResolver().worldPoint(
            for: viewportPoint,
            face: face,
            layout: layout
        )
    )

    #expect(abs(resolved.x - expected.x) < 1.0e-12)
    #expect(abs(resolved.y - expected.y) < 1.0e-12)
    #expect(abs(resolved.z - expected.z) < 1.0e-12)
}

@Test func viewportFaceSurfacePointResolverUsesPerspectiveFaceRaysAndRetainsNearHits() throws {
    let componentID = SelectionComponentID.generatedTopology(
        generatedTopologyTestSubshapeID("feature:body:subshape:test:face:perspective")
    )
    let basis = ViewportProjectionBasis(
        mode: .orbit,
        xDirection: CGVector(dx: 1.0, dy: 0.0),
        yDirection: CGVector(dx: 0.0, dy: -1.0),
        zDirection: .zero
    )
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -1.0, y: -1.0, width: 2.0, height: 2.0),
        size: CGSize(width: 800.0, height: 600.0),
        camera: ViewportCamera(
            zoom: 1.25,
            pan: CGSize(width: 21.0, height: -17.0),
            projection: .standardPerspective
        ),
        basis: basis,
        verticalBounds: -1.0...1.0
    )
    let resolver = ViewportFaceSurfacePointResolver()

    let depthDifferingFace = ViewportBodyTopology.Face(
        componentID: componentID,
        points: [
            Point3D(x: -0.6, y: -0.5, z: -0.12),
            Point3D(x: 0.6, y: -0.5, z: 0.12),
            Point3D(x: 0.6, y: 0.5, z: 0.12),
            Point3D(x: -0.6, y: 0.5, z: -0.12),
        ]
    )
    let expected = Point3D(x: 0.18, y: 0.11, z: 0.036)
    let viewportPoint = try #require(layout.projectedPoint(expected)?.point)
    let resolved = try #require(
        resolver.worldPoint(
            for: viewportPoint,
            face: depthDifferingFace,
            layout: layout
        )
    )
    #expect(abs(resolved.x - expected.x) < 1.0e-9)
    #expect(abs(resolved.y - expected.y) < 1.0e-9)
    #expect(abs(resolved.z - expected.z) < 1.0e-9)

    let nonCoplanarFace = ViewportBodyTopology.Face(
        componentID: componentID,
        points: [
            Point3D(x: -0.6, y: -0.5, z: -0.12),
            Point3D(x: 0.6, y: -0.5, z: 0.12),
            Point3D(x: 0.6, y: 0.5, z: 0.30),
            Point3D(x: -0.6, y: 0.5, z: -0.08),
        ]
    )
    let secondTriangleExpected = Point3D(x: 0.0, y: 0.3, z: 0.102)
    let secondTriangleViewportPoint = try #require(
        layout.projectedPoint(secondTriangleExpected)?.point
    )
    let secondTriangleResolved = try #require(
        resolver.worldPoint(
            for: secondTriangleViewportPoint,
            face: nonCoplanarFace,
            layout: layout
        )
    )
    #expect(
        max(
            abs(secondTriangleResolved.x - secondTriangleExpected.x),
            abs(secondTriangleResolved.y - secondTriangleExpected.y),
            abs(secondTriangleResolved.z - secondTriangleExpected.z)
        ) < 1.0e-9
    )

    let smallFace = ViewportBodyTopology.Face(
        componentID: componentID,
        points: [
            Point3D(x: 0.1, y: -0.1, z: 0.0),
            Point3D(x: 0.1001, y: -0.1, z: 0.0),
            Point3D(x: 0.1, y: -0.0999, z: 0.0),
        ]
    )
    let smallExpected = Point3D(x: 0.10002, y: -0.09997, z: 0.0)
    let smallViewportPoint = try #require(layout.projectedPoint(smallExpected)?.point)
    let smallResolved = try #require(
        resolver.worldPoint(
            for: smallViewportPoint,
            face: smallFace,
            layout: layout
        )
    )
    #expect(
        max(
            abs(smallResolved.x - smallExpected.x),
            abs(smallResolved.y - smallExpected.y),
            abs(smallResolved.z - smallExpected.z)
        ) < 1.0e-9
    )

    let cameraOrigin = try #require(layout.viewportRay(for: layout.fittingCenter)?.origin)
    let nearW = ViewportLayout.minimumPerspectiveW * 0.5
    let farW = 0.8
    let nearPoint = Point3D(
        x: cameraOrigin.x,
        y: cameraOrigin.y,
        z: cameraOrigin.z - nearW
    )
    let farLeft = Point3D(
        x: cameraOrigin.x - 0.2,
        y: cameraOrigin.y - 0.4,
        z: cameraOrigin.z - farW
    )
    let farRight = Point3D(
        x: cameraOrigin.x + 0.2,
        y: cameraOrigin.y - 0.4,
        z: cameraOrigin.z - farW
    )
    let nearCrossingFace = ViewportBodyTopology.Face(
        componentID: componentID,
        points: [nearPoint, farLeft, farRight]
    )
    #expect(layout.projectedPoint(nearPoint) == nil)
    let nearParameter = 2.0e-5
    let nearWRetained = nearW + (farW - nearW) * nearParameter
    let nearExpected = Point3D(
        x: cameraOrigin.x,
        y: cameraOrigin.y - 0.4 * nearParameter,
        z: cameraOrigin.z - nearWRetained
    )
    let nearViewportPoint = try #require(layout.projectedPoint(nearExpected)?.point)
    let nearResolved = try #require(
        resolver.worldPoint(
            for: nearViewportPoint,
            face: nearCrossingFace,
            layout: layout
        )
    )
    #expect(abs(nearResolved.x - nearExpected.x) < 1.0e-8)
    #expect(abs(nearResolved.y - nearExpected.y) < 1.0e-8)
    #expect(abs(nearResolved.z - nearExpected.z) < 1.0e-8)

    let outsideParameter = 1.5
    let outsideW = nearW + (farW - nearW) * outsideParameter
    let outsidePoint = Point3D(
        x: cameraOrigin.x,
        y: cameraOrigin.y - 0.4 * outsideParameter,
        z: cameraOrigin.z - outsideW
    )
    let outsideViewportPoint = try #require(layout.projectedPoint(outsidePoint)?.point)
    #expect(
        resolver.worldPoint(
            for: outsideViewportPoint,
            face: nearCrossingFace,
            layout: layout
        ) == nil
    )

    let parallelFace = ViewportBodyTopology.Face(
        componentID: componentID,
        points: [
            Point3D(x: 0.0, y: -0.4, z: -0.4),
            Point3D(x: 0.0, y: 0.4, z: -0.4),
            Point3D(x: 0.0, y: 0.4, z: 0.4),
        ]
    )
    #expect(resolver.worldPoint(for: layout.fittingCenter, face: parallelFace, layout: layout) == nil)

    let behindFace = ViewportBodyTopology.Face(
        componentID: componentID,
        points: [
            Point3D(x: -0.4, y: -0.4, z: cameraOrigin.z + 0.5),
            Point3D(x: 0.4, y: -0.4, z: cameraOrigin.z + 0.5),
            Point3D(x: 0.0, y: 0.4, z: cameraOrigin.z + 0.5),
        ]
    )
    #expect(resolver.worldPoint(for: layout.fittingCenter, face: behindFace, layout: layout) == nil)

    let degenerateFace = ViewportBodyTopology.Face(
        componentID: componentID,
        points: [
            Point3D(x: -0.4, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.4, y: 0.0, z: 0.0),
        ]
    )
    #expect(resolver.worldPoint(for: layout.fittingCenter, face: degenerateFace, layout: layout) == nil)
}

@MainActor
@Test func viewportSurfaceContinuityOverlayShowsSelectedSurfaceObjectAdjacency() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface Continuity",
        sourceMesh: viewportSurfaceContinuityPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceNodeID = try #require(bodySceneNodeID(for: featureID, in: document))
    let summary = try SurfaceContinuityService().summarize(
        document: document,
        displayUnit: .millimeter
    )
    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    var selection = SelectionModel()
    try selection.selectTarget(
        SelectionTarget(sceneNodeID: surfaceNodeID),
        in: document
    )

    let overlay = ViewportSurfaceContinuityOverlay.build(
        result: summary,
        scene: scene,
        selection: selection,
        document: document
    )

    let item = try #require(overlay.items.first)
    #expect(overlay.items.count == 1)
    #expect(item.continuity == .g2)
    #expect(item.requiresCurvatureContinuitySolve == false)
    #expect(item.edgePersistentName.contains("/polySpline.edge:source:"))
    #expect(abs(item.start.x - 0.01) <= 1.0e-12)
    #expect(abs(item.end.x - 0.01) <= 1.0e-12)
}

@MainActor
@Test func viewportSurfaceContinuityOverlayFiltersToSelectedGeneratedFace() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface Face Continuity",
        sourceMesh: viewportSurfaceContinuityPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceNodeID = try #require(bodySceneNodeID(for: featureID, in: document))
    let summary = try SurfaceContinuityService().summarize(
        document: document,
        displayUnit: .millimeter
    )
    let adjacency = try #require(summary.adjacencies.first)
    let faceName = try #require(adjacency.firstFacePersistentName)
    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    var selection = SelectionModel()
    try selection.selectTarget(
        SelectionTarget(
            sceneNodeID: surfaceNodeID,
            component: .face(.generatedTopology(
                try #require(GeneratedSubshapeIdentity.subshapeID(from: faceName))
            ))
        ),
        in: document
    )

    let overlay = ViewportSurfaceContinuityOverlay.build(
        result: summary,
        scene: scene,
        selection: selection,
        document: document
    )

    #expect(overlay.items.count == 1)
    #expect(overlay.items.first?.continuity == .g2)
}

@MainActor
@Test func viewportSurfaceAnalysisOverlayShowsSelectedSurfaceObjectCombs() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface Analysis",
        sourceMesh: viewportSurfaceContinuityPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceNodeID = try #require(bodySceneNodeID(for: featureID, in: document))
    let analysis = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .low))
        .analyze(document: document, displayUnit: .millimeter)
    var selection = SelectionModel()
    try selection.selectTarget(
        SelectionTarget(sceneNodeID: surfaceNodeID),
        in: document
    )

    let overlay = ViewportSurfaceAnalysisOverlay.build(
        result: analysis,
        selection: selection,
        document: document
    )

    #expect(overlay.items.count == 36)
    #expect(overlay.principalDirectionItems.count == 18)
    #expect(overlay.boundaryItems.count == 2)
    #expect(overlay.items.contains { $0.direction == .u })
    #expect(overlay.items.contains { $0.direction == .v })
    #expect(overlay.boundaryItems.allSatisfy { $0.role == .outer })
    #expect(overlay.boundaryItems.allSatisfy { $0.points.count == 4 })
    #expect(overlay.boundaryItems.allSatisfy { $0.isClosed })
    #expect(overlay.items.allSatisfy { $0.normalChangePerLength <= 1.0e-8 })
    #expect(overlay.items.allSatisfy { abs($0.normalCurvature) <= 1.0e-8 })
    #expect(overlay.principalDirectionItems.allSatisfy { abs($0.minimumPrincipalCurvature) <= 1.0e-8 })
    #expect(overlay.principalDirectionItems.allSatisfy { abs($0.maximumPrincipalCurvature) <= 1.0e-8 })
}

@MainActor
@Test func viewportSurfaceAnalysisOverlayFiltersToSelectedGeneratedFace() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface Face Analysis",
        sourceMesh: viewportSurfaceContinuityPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceNodeID = try #require(bodySceneNodeID(for: featureID, in: document))
    let analysis = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .low))
        .analyze(document: document, displayUnit: .millimeter)
    let face = try #require(analysis.faces.first)
    let faceName = try #require(face.faceSubshapeIDs.first)
    var selection = SelectionModel()
    try selection.selectTarget(
        SelectionTarget(
            sceneNodeID: surfaceNodeID,
            component: .face(.generatedTopology(
                try #require(GeneratedSubshapeIdentity.subshapeID(from: faceName))
            ))
        ),
        in: document
    )

    let overlay = ViewportSurfaceAnalysisOverlay.build(
        result: analysis,
        selection: selection,
        document: document
    )

    #expect(overlay.items.count == 18)
    #expect(overlay.principalDirectionItems.count == 9)
    #expect(overlay.boundaryItems.count == 1)
    #expect(Set(overlay.items.map(\.faceID)) == [face.faceID])
    #expect(Set(overlay.principalDirectionItems.map(\.faceID)) == [face.faceID])
    #expect(Set(overlay.boundaryItems.map(\.faceID)) == [face.faceID])
}

@MainActor
@Test func viewportSurfaceAnalysisOverlayRespectsDisplayOptions() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface Analysis Options",
        sourceMesh: viewportSurfaceContinuityPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceNodeID = try #require(bodySceneNodeID(for: featureID, in: document))
    let analysis = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .low))
        .analyze(document: document, displayUnit: .millimeter)
    var selection = SelectionModel()
    try selection.selectTarget(
        SelectionTarget(sceneNodeID: surfaceNodeID),
        in: document
    )

    let principalOnly = ViewportSurfaceAnalysisOverlay.build(
        result: analysis,
        selection: selection,
        document: document,
        options: ViewportSurfaceAnalysisOptions(
            showsCurvatureCombs: false,
            showsPrincipalDirections: true,
            showsTrimBoundaries: false
        )
    )
    let hidden = ViewportSurfaceAnalysisOverlay.build(
        result: analysis,
        selection: selection,
        document: document,
        options: ViewportSurfaceAnalysisOptions(
            showsCurvatureCombs: false,
            showsPrincipalDirections: false,
            showsTrimBoundaries: false
        )
    )

    #expect(principalOnly.items.isEmpty)
    #expect(principalOnly.principalDirectionItems.count == 18)
    #expect(principalOnly.boundaryItems.isEmpty)
    #expect(hidden.items.isEmpty)
    #expect(hidden.principalDirectionItems.isEmpty)
    #expect(hidden.boundaryItems.isEmpty)
}

@MainActor
@Test func viewportSurfaceAnalysisOverlayReportsPrincipalDirectionsForNonPlanarSurface() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Nonplanar Principal Directions",
        sourceMesh: viewportSurfaceAnalysisSingleQuadMesh(topRightZ: 0.004),
        options: PolySplineOptions()
    )
    let surfaceNodeID = try #require(bodySceneNodeID(for: featureID, in: document))
    let analysis = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .low))
        .analyze(document: document, displayUnit: .millimeter)
    var selection = SelectionModel()
    try selection.selectTarget(
        SelectionTarget(sceneNodeID: surfaceNodeID),
        in: document
    )

    let overlay = ViewportSurfaceAnalysisOverlay.build(
        result: analysis,
        selection: selection,
        document: document
    )

    #expect(overlay.principalDirectionItems.count == 9)
    #expect(overlay.principalDirectionItems.contains { abs($0.minimumPrincipalCurvature) > 1.0e-6 })
    #expect(overlay.principalDirectionItems.contains { abs($0.maximumPrincipalCurvature) > 1.0e-6 })
    #expect(overlay.principalDirectionItems.allSatisfy {
        abs($0.minimumPrincipalDirection.length - 1.0) <= 1.0e-8
    })
    #expect(overlay.principalDirectionItems.allSatisfy {
        abs($0.maximumPrincipalDirection.length - 1.0) <= 1.0e-8
    })
}

@MainActor
@Test func viewportSceneBuilderExposesVisibleSurfaceControlPointDisplays() async throws {
    var document = DesignDocument.empty()
    var workspaceState = WorkspaceState()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface CV Display",
        sourceMesh: viewportSurfaceAnalysisSingleQuadMesh(topRightZ: 0.0),
        options: PolySplineOptions()
    )
    let initialScene = ViewportSceneBuilder().build(
        document: document,
        ruler: workspaceState.ruler
    )
    let initialBody = try #require(initialScene.items.first { $0.featureID == featureID })
    guard case .body(let initialComponent) = initialBody.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    #expect(initialComponent.surfaceControlPointDisplays.isEmpty)

    let summary = try SurfaceSourceSummaryService().summarize(
        document: document,
        displayUnit: workspaceState.displayUnit
    )
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    _ = try workspaceState.apply(
        .setSurfaceControlPointDisplay(
            target: try #require(controlPoint.selectionReference),
            isVisible: true
        ),
        document: document
    )

    let visibleScene = ViewportSceneBuilder().build(
        document: document,
        ruler: workspaceState.ruler,
        overlayState: viewportSceneOverlayState(from: workspaceState)
    )
    let visibleBody = try #require(visibleScene.items.first { $0.featureID == featureID })
    guard case .body(let visibleComponent) = visibleBody.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    let display = try #require(visibleComponent.surfaceControlPointDisplays.first)
    #expect(visibleComponent.surfaceControlPointDisplays.count == 1)
    #expect(display.selectionReference == controlPoint.selectionReference)
    #expect(display.uIndex == 1)
    #expect(display.vIndex == 1)
    #expect(display.isBoundary == false)
    #expect(abs(display.point.x - controlPoint.point.x) <= 1.0e-12)
    #expect(abs(display.point.y - controlPoint.point.y) <= 1.0e-12)
    #expect(abs(display.point.z - controlPoint.point.z) <= 1.0e-12)

    _ = try workspaceState.apply(
        .setSurfaceControlPointDisplay(
            target: try #require(controlPoint.selectionReference),
            isVisible: false
        ),
        document: document
    )
    let hiddenScene = ViewportSceneBuilder().build(
        document: document,
        ruler: workspaceState.ruler,
        overlayState: viewportSceneOverlayState(from: workspaceState)
    )
    let hiddenBody = try #require(hiddenScene.items.first { $0.featureID == featureID })
    guard case .body(let hiddenComponent) = hiddenBody.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    #expect(hiddenComponent.surfaceControlPointDisplays.isEmpty)
}

@Test func viewportSceneBuilderExposesAuthoredSurfaceTrimEndpointDisplays() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createBSplineSurface(
        name: "Viewport Surface Trim Endpoint",
        surface: viewportDirectBSplineSurface()
    )
    let summary = try SurfaceSourceSummaryService().summarize(
        document: document,
        displayUnit: .millimeter
    )
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = SurfaceTrimLoop(
        role: .outer,
        parameterCurves: [
            .polyline([
                SurfaceParameter(u: 0.2, v: 0.2),
                SurfaceParameter(u: 0.8, v: 0.25),
            ]),
            .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ]),
            .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ]),
        ]
    )
    try document.setSurfaceTrimLoops(target: faceReference, trimLoops: [trimLoop])
    // The authored trim node owns the visible body, so its scene item
    // carries the trim displays.
    let trimFeatureID = try #require(
        document.existingSurfaceTrimOperation(for: featureID)?.node.id
    )

    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let body = try #require(scene.items.first { $0.featureID == trimFeatureID })
    guard case .body(let component) = body.kind else {
        Issue.record("Expected a B-spline surface body scene item.")
        return
    }
    #expect(component.surfaceTrimEndpointDisplays.count == 6)
    let startDisplay = try #require(component.surfaceTrimEndpointDisplays.first { display in
        display.endpoint == .start
    })
    #expect(startDisplay.u == 0.2)
    #expect(startDisplay.v == 0.2)
    #expect(startDisplay.tangentU.length > 0.0)
    #expect(startDisplay.tangentV.length > 0.0)
}

@Test func viewportSceneBuilderExposesAuthoredSurfaceTrimControlPointDisplays() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createBSplineSurface(
        name: "Viewport Surface Trim Control Point",
        surface: viewportDirectBSplineSurface()
    )
    let summary = try SurfaceSourceSummaryService().summarize(
        document: document,
        displayUnit: .millimeter
    )
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = SurfaceTrimLoop(
        role: .outer,
        parameterCurves: [
            .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.52, y: 0.42),
                    Point2D(x: 0.8, y: 0.25),
                ]
            )),
            .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ]),
            .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ]),
        ]
    )
    try document.setSurfaceTrimLoops(target: faceReference, trimLoops: [trimLoop])
    // The authored trim node owns the visible body, so its scene item
    // carries the trim displays.
    let trimFeatureID = try #require(
        document.existingSurfaceTrimOperation(for: featureID)?.node.id
    )

    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let body = try #require(scene.items.first { $0.featureID == trimFeatureID })
    guard case .body(let component) = body.kind else {
        Issue.record("Expected a B-spline surface body scene item.")
        return
    }
    #expect(component.surfaceTrimControlPointDisplays.count == 1)
    let controlPointDisplay = try #require(component.surfaceTrimControlPointDisplays.first)
    let firstEndpointDisplay = try #require(component.surfaceTrimEndpointDisplays.first)
    #expect(controlPointDisplay.selectionReference == firstEndpointDisplay.selectionReference)
    #expect(controlPointDisplay.controlPointIndex == 1)
    #expect(controlPointDisplay.u == 0.52)
    #expect(controlPointDisplay.v == 0.42)
    #expect(controlPointDisplay.tangentU.length > 0.0)
    #expect(controlPointDisplay.tangentV.length > 0.0)
}

@Test func viewportSceneBuilderExposesAuthoredSurfaceTrimParameterDisplays() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createBSplineSurface(
        name: "Viewport Surface Trim Parameters",
        surface: viewportDirectBSplineSurface()
    )
    let summary = try SurfaceSourceSummaryService().summarize(
        document: document,
        displayUnit: .millimeter
    )
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = SurfaceTrimLoop(
        role: .outer,
        parameterCurves: [
            .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.4, y: 0.42),
                    Point2D(x: 0.62, y: 0.38),
                    Point2D(x: 0.8, y: 0.25),
                ]
            )),
            .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ]),
            .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ]),
        ]
    )
    try document.setSurfaceTrimLoops(target: faceReference, trimLoops: [trimLoop])
    // The authored trim node owns the visible body, so its scene item
    // carries the trim displays.
    let trimFeatureID = try #require(
        document.existingSurfaceTrimOperation(for: featureID)?.node.id
    )

    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let body = try #require(scene.items.first { $0.featureID == trimFeatureID })
    guard case .body(let component) = body.kind else {
        Issue.record("Expected a B-spline surface body scene item.")
        return
    }
    #expect(component.surfaceTrimKnotDisplays.count == 1)
    #expect(component.surfaceTrimSpanDisplays.count == 2)
    let knotDisplay = try #require(component.surfaceTrimKnotDisplays.first)
    let spanDisplay = try #require(component.surfaceTrimSpanDisplays.first)
    guard case .surface(.trimKnot(let knotReference)) = knotDisplay.selectionReference else {
        Issue.record("Expected a trim p-curve knot selection reference.")
        return
    }
    guard case .surface(.trimSpan(let spanReference)) = spanDisplay.selectionReference else {
        Issue.record("Expected a trim p-curve span selection reference.")
        return
    }
    #expect(knotReference.knotIndex == 3)
    #expect(spanReference.spanIndex == 0)
}

@Test func viewportSceneBuilderExposesDirectSurfaceBasisDisplays() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createBSplineSurface(
        name: "Viewport Surface Basis Parameters",
        surface: viewportEditableDirectBSplineSurface()
    )

    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let body = try #require(scene.items.first { $0.featureID == featureID })
    guard case .body(let component) = body.kind else {
        Issue.record("Expected a B-spline surface body scene item.")
        return
    }
    #expect(component.surfaceKnotDisplays.count == 2)
    #expect(component.surfaceSpanDisplays.count == 4)
    let knotDisplay = try #require(component.surfaceKnotDisplays.first)
    let spanDisplay = try #require(component.surfaceSpanDisplays.first)
    guard case .surface(.knot(let knotReference)) = knotDisplay.selectionReference else {
        Issue.record("Expected a surface knot selection reference.")
        return
    }
    guard case .surface(.span(let spanReference)) = spanDisplay.selectionReference else {
        Issue.record("Expected a surface span selection reference.")
        return
    }
    #expect(knotReference.direction == knotDisplay.direction)
    #expect(knotReference.knotIndex == knotDisplay.knotIndex)
    #expect(spanReference.direction == spanDisplay.direction)
    #expect(spanReference.spanIndex == spanDisplay.spanIndex)
}

@MainActor
@Test func viewportSceneBuilderExposesVisibleSurfaceFrameDisplays() async throws {
    var document = DesignDocument.empty()
    var workspaceState = WorkspaceState()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface Frame Display",
        sourceMesh: viewportSurfaceAnalysisSingleQuadMesh(topRightZ: 0.0),
        options: PolySplineOptions()
    )
    let initialScene = ViewportSceneBuilder().build(
        document: document,
        ruler: workspaceState.ruler
    )
    let initialBody = try #require(initialScene.items.first { $0.featureID == featureID })
    guard case .body(let initialComponent) = initialBody.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    #expect(initialComponent.surfaceFrameDisplays.isEmpty)

    let summary = try SurfaceSourceSummaryService().summarize(
        document: document,
        displayUnit: workspaceState.displayUnit
    )
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 2 && $0.vIndex == 1 })
    let query = SurfaceFrameQuery(selectionReference: controlPoint.selectionReference)
    _ = try workspaceState.apply(
        .setSurfaceFrameDisplay(
            query: query,
            isVisible: true
        ),
        document: document
    )

    let expectedFrame = try #require(SurfaceFrameService().resolve(
        document: document,
        queries: [query],
        displayUnit: workspaceState.displayUnit
    ).frames.first)
    let visibleScene = ViewportSceneBuilder().build(
        document: document,
        ruler: workspaceState.ruler,
        overlayState: viewportSceneOverlayState(from: workspaceState)
    )
    let visibleBody = try #require(visibleScene.items.first { $0.featureID == featureID })
    guard case .body(let visibleComponent) = visibleBody.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    let display = try #require(visibleComponent.surfaceFrameDisplays.first)
    #expect(visibleComponent.surfaceFrameDisplays.count == 1)
    #expect(display.query == query)
    #expect(abs(display.u - (2.0 / 3.0)) <= 1.0e-12)
    #expect(abs(display.v - (1.0 / 3.0)) <= 1.0e-12)
    #expect(abs(display.position.x - expectedFrame.position.x) <= 1.0e-12)
    #expect(abs(display.position.y - expectedFrame.position.y) <= 1.0e-12)
    #expect(abs(display.position.z - expectedFrame.position.z) <= 1.0e-12)
    #expect(abs(display.uAxis.length - 1.0) <= 1.0e-8)
    #expect(abs(display.vAxis.length - 1.0) <= 1.0e-8)
    #expect(abs(display.normal.length - 1.0) <= 1.0e-8)

    _ = try workspaceState.apply(
        .setSurfaceFrameDisplay(
            query: query,
            isVisible: false
        ),
        document: document
    )
    let hiddenScene = ViewportSceneBuilder().build(
        document: document,
        ruler: workspaceState.ruler,
        overlayState: viewportSceneOverlayState(from: workspaceState)
    )
    let hiddenBody = try #require(hiddenScene.items.first { $0.featureID == featureID })
    guard case .body(let hiddenComponent) = hiddenBody.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    #expect(hiddenComponent.surfaceFrameDisplays.isEmpty)
}

@MainActor
@Test func viewportSceneBuilderCreatesBodyItemForSupportedStraightPathSweep() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Viewport Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Viewport Sweep Path",
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
    let session = EditorSession(document: document)
    let result = try session.execute(.createSweep(
        name: "Viewport Sweep",
        sections: [.profile(ProfileReference(featureID: profileID))],
        path: SweepPathReference(featureID: pathID),
        guides: [],
        targets: [],
        options: SweepOptions()
    ))

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    guard case .body(let component) = bodyItem.kind else {
        Issue.record("Expected a sweep body scene item.")
        return
    }

    #expect(result.commandName == "createSweep")
    #expect(session.evaluationStatus == .valid)
    #expect(abs(component.sizeXMeters - 0.004) <= 1.0e-12)
    #expect(abs(component.sizeYMeters - 0.02) <= 1.0e-12)
    #expect(abs(component.sizeZMeters - 0.002) <= 1.0e-12)
    #expect(bodyItem.sourceFeatureID == profileID)
}

@MainActor
@Test func viewportSceneBuilderShowsNoBodyItemForRejectedTwistedScaledStraightPathSweep() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Viewport Twisted Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Viewport Twisted Sweep Path",
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
    let session = EditorSession(document: document)
    // The exact kernel rejects twisted sweeps, so the transaction rolls back
    // and the viewport keeps showing only the source sketches.
    var caught: EditorError?
    do {
        _ = try session.execute(.createSweep(
            name: "Viewport Twisted Scaled Sweep",
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [],
            targets: [],
            options: SweepOptions(
                twistAngle: .angle(90.0, .degree),
                endScale: .constant(.scalar(0.5))
            )
        ))
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .evaluationFailed)
    #expect(caught?.message.contains("sweepTwistUnavailable") == true)
    #expect(session.document.cadDocument.designGraph.order == [profileID, pathID])

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    #expect(scene.items.allSatisfy { item in
        if case .body = item.kind {
            return false
        }
        return true
    })
}

@MainActor
@Test func viewportSceneBuilderCreatesMeshBodyItemForSheetSweep() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Viewport Sheet Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Viewport Sheet Sweep Path",
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
    let session = EditorSession(document: document)
    let result = try session.execute(.createSweep(
        name: "Viewport Sheet Sweep",
        sections: [.profile(ProfileReference(featureID: profileID))],
        path: SweepPathReference(featureID: pathID),
        guides: [],
        targets: [],
        options: SweepOptions(resultKind: .sheet)
    ))

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    guard case .body(let component) = bodyItem.kind else {
        Issue.record("Expected a sheet sweep body scene item.")
        return
    }
    let mesh = try #require(component.mesh)

    #expect(result.commandName == "createSweep")
    #expect(session.evaluationStatus == .valid)
    #expect(mesh.positions.count > 0)
    #expect(mesh.indices.count > 0)
    #expect(mesh.indices.count % 3 == 0)
    #expect(bodyItem.sourceFeatureID == profileID)
}

@MainActor
@Test func viewportSceneBuilderCreatesMeshBodyItemForCurveSectionSheetSweep() async throws {
    var document = DesignDocument.empty()
    let sectionID = try document.createLineSketch(
        name: "Viewport Curve Sheet Section",
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
    let pathID = try document.createLineSketch(
        name: "Viewport Curve Sheet Path",
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
    let session = EditorSession(document: document)
    let result = try session.execute(.createSweep(
        name: "Viewport Curve Section Sheet Sweep",
        sections: [.curve(SweepCurveSectionReference(featureID: sectionID))],
        path: SweepPathReference(featureID: pathID),
        guides: [],
        targets: [],
        options: SweepOptions(resultKind: .sheet)
    ))

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    guard case .body(let component) = bodyItem.kind else {
        Issue.record("Expected a curve-section sheet sweep body scene item.")
        return
    }
    let mesh = try #require(component.mesh)

    #expect(result.commandName == "createSweep")
    #expect(session.evaluationStatus == .valid)
    #expect(mesh.positions.count > 0)
    #expect(mesh.indices.count > 0)
    #expect(mesh.indices.count % 3 == 0)
    #expect(bodyItem.sourceFeatureID == sectionID)
}

@MainActor
@Test func viewportSceneBuilderCreatesMeshBodyItemForPointGuidedStraightPathSweep() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Viewport Guided Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Viewport Guided Sweep Path",
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
    let guideID = try document.createLineSketch(
        name: "Viewport Guided Sweep Guide",
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
    let session = EditorSession(document: document)
    let result = try session.execute(.createSweep(
        name: "Viewport Point Guided Sweep",
        sections: [.profile(ProfileReference(featureID: profileID))],
        path: SweepPathReference(featureID: pathID),
        guides: [SweepGuideReference(featureID: guideID)],
        targets: [],
        options: SweepOptions(guideMethod: .point)
    ))

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    guard case .body(let component) = bodyItem.kind else {
        Issue.record("Expected a guided sweep body scene item.")
        return
    }
    let mesh = try #require(component.mesh)

    #expect(result.commandName == "createSweep")
    #expect(session.evaluationStatus == .valid)
    #expect(mesh.positions.count > 0)
    #expect(mesh.indices.count > 0)
    #expect(mesh.indices.count % 3 == 0)
    #expect(bodyItem.sourceFeatureID == profileID)
}

@MainActor
@Test func viewportSceneBuilderCreatesMeshBodyItemForCurvedPathSweep() async throws {
    let setup = try makeCurvedSweepViewportSession()

    let scene = ViewportSceneBuilder().build(document: setup.session.document, ruler: setup.session.workspaceState.ruler)
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    guard case .body(let component) = bodyItem.kind else {
        Issue.record("Expected a curved sweep body scene item.")
        return
    }
    let mesh = try #require(component.mesh)
    let topology = try #require(component.topology)

    #expect(setup.commandResult.commandName == "createSweep")
    #expect(setup.session.evaluationStatus == .valid)
    #expect(bodyItem.sourceFeatureID == setup.profileID)
    #expect(mesh.positions.count > 8)
    #expect(mesh.indices.count > 36)
    // The exact circular sweep of a rectangular profile is a closed box-like
    // solid: start + end + four side faces.
    #expect(topology.faces.count == 6)
    #expect(topology.edges.count == 12)
    #expect(topology.vertices.count == 8)
    #expect(component.sizeYMeters > 0.05)
    #expect(component.sizeZMeters > 0.05)
}

@MainActor
@Test func viewportSceneBuilderPreservesFilletArcPrimitive() async throws {
    let session = EditorSession()
    let sketchResult = try session.execute(
        .createRectangleSketch(
            name: "Fillet Profile",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter)
        )
    )
    let sketchFeatureID = try #require(sketchResult.primaryFeatureID)
    _ = try session.execute(
        .extrudeProfile(
            name: "Fillet Body",
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .length(10.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(bodyFeatureID)
    }?.key)
    _ = try session.execute(.filletBodyEdges(
        targets: [SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop))],
        radius: .length(1.0, .millimeter),
        segmentCount: 6
    ))

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    guard case .sketch(let primitives) = sketchItem.kind else {
        Issue.record("Expected a sketch scene item.")
        return
    }

    #expect(primitives.contains { primitive in
        if case .arc(_, _, let radiusMeters, let startAngle, let endAngle, _) = primitive {
            return abs(radiusMeters - 0.001) <= 1.0e-9
                && abs(startAngle) <= 1.0e-9
                && abs(endAngle - Double.pi / 2.0) <= 1.0e-9
        }
        return false
    })
}

@MainActor
@Test func viewportSceneBuilderPreservesDirectArcSketchPrimitive() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Viewport Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(3.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(120.0, .degree)
        )
    )

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    guard case .sketch(let primitives) = sketchItem.kind else {
        Issue.record("Expected a sketch scene item.")
        return
    }

    #expect(primitives.contains { primitive in
        if case .arc(_, let center, let radiusMeters, let startAngle, let endAngle, _) = primitive {
            return abs(center.x - 0.002) <= 1.0e-9
                && abs(center.y - 0.003) <= 1.0e-9
                && abs(radiusMeters - 0.004) <= 1.0e-9
                && abs(startAngle) <= 1.0e-9
                && abs(endAngle - Double.pi * 2.0 / 3.0) <= 1.0e-9
        }
        return false
    })
}

@MainActor
@Test func viewportSceneBuilderPreservesSplineSketchPrimitive() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Viewport Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    guard case .sketch(let primitives) = sketchItem.kind else {
        Issue.record("Expected a sketch scene item.")
        return
    }

    #expect(primitives.contains { primitive in
        if case .spline(_, let points, let controlPoints, let sketchPlane) = primitive {
            return points.count == 33
                && controlPoints.count == 4
                && sketchPlane == .xy
                && abs(points.first?.x ?? -1.0) <= 1.0e-12
                && abs((points.last?.x ?? -1.0) - 0.008) <= 1.0e-12
                && abs(controlPoints[1].x - 0.002) <= 1.0e-12
                && abs(controlPoints[1].y - 0.004) <= 1.0e-12
        }
        return false
    })
}

@MainActor
@Test func viewportSceneBuilderCreatesSketchRegionSelectionCandidates() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Viewport Selectable Region",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    let region = try #require(sketchItem.sketchRegions.first)

    #expect(sketchItem.sketchRegions.count == 1)
    #expect(region.componentID == .profileRegion(featureID: sketchItem.featureID, profileIndex: 0))
    #expect(region.points.count == 4)
}

@Test func viewportLayoutUnprojectsProjectedMicrometerModelPoint() {
    let bounds = CGRect(
        x: -0.000_002,
        y: -0.000_003,
        width: 0.000_004,
        height: 0.000_006
    )
    let size = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportLayout(modelBounds: bounds, size: size)
    let modelPoint = CGPoint(x: 0.000_001, y: -0.000_002)
    let projectedPoint = layout.project(modelPoint)
    let unprojectedPoint = layout.unproject(projectedPoint)
    let expectedBounds = projectedBounds(
        width: bounds.width,
        height: bounds.height,
        basis: layout.basis
    )
    let expectedScale = min(
        size.width / expectedBounds.width,
        size.height / expectedBounds.height
    )

    #expect(abs(layout.scale - expectedScale) < expectedScale * 1.0e-12)
    #expect(abs(unprojectedPoint.x - modelPoint.x) < 1.0e-15)
    #expect(abs(unprojectedPoint.y - modelPoint.y) < 1.0e-15)
}

@Test func viewportLayoutAppliesExplicitFittingInsets() {
    let bounds = CGRect(x: -2.0, y: -1.0, width: 4.0, height: 2.0)
    let size = CGSize(width: 800.0, height: 600.0)
    let fittingInsets = ViewportLayout.FittingInsets(
        top: 30.0,
        leading: 40.0,
        bottom: 50.0,
        trailing: 60.0
    )
    let layout = ViewportLayout(
        modelBounds: bounds,
        size: size,
        fittingInsets: fittingInsets
    )
    let expectedBounds = projectedBounds(
        width: bounds.width,
        height: bounds.height,
        basis: layout.basis
    )
    let fittingSize = CGSize(width: 700.0, height: 520.0)
    let expectedScale = min(
        fittingSize.width / expectedBounds.width,
        fittingSize.height / expectedBounds.height
    )
    let expectedCenter = CGPoint(x: 390.0, y: 290.0)
    let projectedOrigin = layout.project(Point3D.origin)

    #expect(layout.fittingInsets == fittingInsets)
    #expect(layout.fittingCenter == expectedCenter)
    #expect(layout.center == CGPoint(x: 400, y: 300))
    #expect(abs(layout.scale - expectedScale) < expectedScale * 1.0e-12)
    #expect(abs(projectedOrigin.x - 400) < 1.0e-9)
    #expect(abs(projectedOrigin.y - 300) < 1.0e-9)
}

@Test func viewportLayoutProjectsFootprintAlongCoordinateGridBasis() {
    let bounds = CGRect(
        x: -0.02,
        y: -0.01,
        width: 0.04,
        height: 0.02
    )
    let layout = ViewportLayout(
        modelBounds: bounds,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let footprint = layout.projectedFootprint(bounds)
    let grid = ViewportProjectionBasis.isometric

    let xEdge = CGVector(
        dx: footprint.bottomRight.x - footprint.bottomLeft.x,
        dy: footprint.bottomRight.y - footprint.bottomLeft.y
    )
    let zEdge = CGVector(
        dx: footprint.topLeft.x - footprint.bottomLeft.x,
        dy: footprint.topLeft.y - footprint.bottomLeft.y
    )

    #expect(isParallel(xEdge, grid.xDirection))
    #expect(isParallel(zEdge, grid.zDirection))
    #expect(footprint.bounds.width > 0.0)
    #expect(footprint.bounds.height > 0.0)
}

@Test func viewportProfileFaceDragMappingMatchesFaceOffsetCommandSigns() {
    #expect(ViewportProfileFaceDragMapping.distance(for: .right, xDelta: 0.003, yDelta: 0.002, zDelta: 0.004) == 0.003)
    #expect(ViewportProfileFaceDragMapping.distance(for: .side, xDelta: 0.003, yDelta: 0.002, zDelta: 0.004) == 0.003)
    #expect(ViewportProfileFaceDragMapping.distance(for: .left, xDelta: 0.003, yDelta: 0.002, zDelta: 0.004) == -0.003)
    #expect(ViewportProfileFaceDragMapping.distance(for: .top, xDelta: 0.003, yDelta: 0.002, zDelta: 0.004) == 0.004)
    #expect(ViewportProfileFaceDragMapping.distance(for: .bottom, xDelta: 0.003, yDelta: 0.002, zDelta: 0.004) == -0.004)
    #expect(ViewportProfileFaceDragMapping.distance(for: .front, xDelta: 0.003, yDelta: 0.002, zDelta: 0.004) == -0.002)
    #expect(ViewportProfileFaceDragMapping.distance(for: .back, xDelta: 0.003, yDelta: 0.002, zDelta: 0.004) == 0.002)
}

@Test func viewportProfileEdgeChamferMappingUsesCornerInwardDirections() {
    #expect(ViewportProfileEdgeChamferMapping.distance(for: .leftBottom, xDelta: 0.002, zDelta: 0.002) == 0.002)
    #expect(ViewportProfileEdgeChamferMapping.distance(for: .rightBottom, xDelta: -0.002, zDelta: 0.002) == 0.002)
    #expect(ViewportProfileEdgeChamferMapping.distance(for: .rightTop, xDelta: -0.002, zDelta: -0.002) == 0.002)
    #expect(ViewportProfileEdgeChamferMapping.distance(for: .leftTop, xDelta: 0.002, zDelta: -0.002) == 0.002)
    #expect(ViewportProfileEdgeChamferMapping.distance(for: .leftBottom, xDelta: -0.002, zDelta: -0.002) == nil)
    #expect(ViewportProfileEdgeChamferMapping.distance(for: .rightTop, xDelta: 0.002, zDelta: 0.002) == nil)
}

@Test func viewportProfileEdgeFilletMappingUsesCornerInwardDirectionsAsRadius() {
    #expect(ViewportProfileEdgeFilletMapping.radius(for: .leftBottom, xDelta: 0.002, zDelta: 0.002) == 0.002)
    #expect(ViewportProfileEdgeFilletMapping.radius(for: .rightBottom, xDelta: -0.002, zDelta: 0.002) == 0.002)
    #expect(ViewportProfileEdgeFilletMapping.radius(for: .rightTop, xDelta: -0.002, zDelta: -0.002) == 0.002)
    #expect(ViewportProfileEdgeFilletMapping.radius(for: .leftTop, xDelta: 0.002, zDelta: -0.002) == 0.002)
    #expect(ViewportProfileEdgeFilletMapping.radius(for: .leftBottom, xDelta: -0.002, zDelta: -0.002) == nil)
    #expect(ViewportProfileEdgeFilletMapping.radius(for: .rightTop, xDelta: 0.002, zDelta: 0.002) == nil)
}

@Test func viewportRegionOffsetAffordanceMapsArrowDragToSignedDistance() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0.0, y: 0.0, width: 2.0, height: 2.0),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let geometry = try #require(
        ViewportRegionOffsetAffordanceGeometry(
            points: [
                CGPoint(x: 0.0, y: 0.0),
                CGPoint(x: 1.0, y: 0.0),
                CGPoint(x: 1.0, y: 1.0),
                CGPoint(x: 0.0, y: 1.0),
            ],
            layout: layout
        )
    )

    let start = try #require(geometry.projectedTip(layout: layout))
    let outwardEnd = try #require(geometry.projectedTip(layout: layout, distanceMeters: 0.25))
    let inwardEnd = try #require(geometry.projectedTip(layout: layout, distanceMeters: -0.125))

    #expect(geometry.modelDirection.x > 0.0)
    let outwardDistance = try #require(geometry.offsetDistance(start: start, current: outwardEnd, layout: layout))
    let inwardDistance = try #require(geometry.offsetDistance(start: start, current: inwardEnd, layout: layout))
    #expect(abs(outwardDistance - 0.25) < 1.0e-12)
    #expect(abs(inwardDistance + 0.125) < 1.0e-12)
}

@Test func viewportEdgeOffsetAffordanceMapsArrowDragToPositiveDistance() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0.0, y: 0.0, width: 2.0, height: 2.0),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let geometry = try #require(
        ViewportEdgeOffsetAffordanceGeometry(
            edgeStart: CGPoint(x: 300.0, y: 260.0),
            edgeEnd: CGPoint(x: 360.0, y: 260.0),
            supportPoint: CGPoint(x: 330.0, y: 220.0),
            fallbackDirection: CGVector(dx: 1.0, dy: 0.0),
            distanceMeters: 0.5,
            layout: layout
        )
    )

    let start = geometry.projectedTip()
    let fartherEnd = geometry.projectedTip(distanceMeters: 0.75)
    let nearerEnd = geometry.projectedTip(distanceMeters: 0.35)
    let collapsedEnd = geometry.projectedTip(distanceMeters: -0.1)
    let previewSegment = geometry.previewSegment(distanceMeters: 0.75)

    #expect(abs(geometry.projectedDirection.dx) < 1.0e-12)
    #expect(geometry.projectedDirection.dy < 0.0)
    #expect(abs(geometry.offsetDistance(start: start, current: fartherEnd) - 0.75) < 1.0e-12)
    #expect(abs(geometry.offsetDistance(start: start, current: nearerEnd) - 0.35) < 1.0e-12)
    #expect(geometry.offsetDistance(start: start, current: collapsedEnd) > 0.0)
    #expect(abs(previewSegment.start.x - 300.0) < 1.0e-12)
    #expect(abs(previewSegment.end.x - 360.0) < 1.0e-12)
    #expect(previewSegment.start.y < 260.0)
    #expect(abs((previewSegment.end.x - previewSegment.start.x) - 60.0) < 1.0e-12)
    #expect(abs(previewSegment.end.y - previewSegment.start.y) < 1.0e-12)
}

@Test func viewportSlotWidthAffordanceMapsArrowDragToFullWidth() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0.0, y: 0.0, width: 2.0, height: 2.0),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let geometry = try #require(
        ViewportSlotWidthAffordanceGeometry(
            lineStart: CGPoint(x: 0.0, y: 0.0),
            lineEnd: CGPoint(x: 1.0, y: 0.0),
            widthMeters: 1.0,
            layout: layout
        )
    )

    let start = try #require(geometry.projectedTip(layout: layout))
    let widerEnd = try #require(geometry.projectedTip(layout: layout, widthMeters: 1.4))
    let narrowerEnd = try #require(geometry.projectedTip(layout: layout, widthMeters: 0.8))

    #expect(abs(geometry.modelDirection.x) < 1.0e-12)
    let widerWidth = try #require(geometry.slotWidth(start: start, current: widerEnd, layout: layout))
    let narrowerWidth = try #require(geometry.slotWidth(start: start, current: narrowerEnd, layout: layout))
    #expect(abs(widerWidth - 1.4) < 1.0e-12)
    #expect(abs(narrowerWidth - 0.8) < 1.0e-12)
}

@Test func viewportSketchVertexOffsetAffordanceMapsArrowDragToPositiveDistance() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 0.0, y: 0.0, width: 2.0, height: 2.0),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let geometry = try #require(
        ViewportSketchVertexOffsetAffordanceGeometry(
            baseModelPoint: CGPoint(x: 0.25, y: 0.25),
            modelDirection: CGPoint(x: 1.0, y: 0.0),
            distanceMeters: 1.0,
            layout: layout
        )
    )

    let start = try #require(geometry.projectedTip(layout: layout))
    let fartherEnd = try #require(geometry.projectedTip(layout: layout, distanceMeters: 1.25))
    let nearerEnd = try #require(geometry.projectedTip(layout: layout, distanceMeters: 0.75))

    #expect(abs(geometry.modelDirection.x - 1.0) < 1.0e-12)
    let fartherDistance = try #require(geometry.offsetDistance(start: start, current: fartherEnd, layout: layout))
    let nearerDistance = try #require(geometry.offsetDistance(start: start, current: nearerEnd, layout: layout))
    #expect(abs(fartherDistance - 1.25) < 1.0e-12)
    #expect(abs(nearerDistance - 0.75) < 1.0e-12)
}

@Test func viewportModelCoordinateMapperProvidesEmptyDocumentDragPlane() throws {
    let document = DesignDocument.empty()
    let ruler = RulerConfiguration.standard(for: .micrometer)
    let mapper = ViewportModelCoordinateMapper(
        document: document,
        ruler: ruler,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let centerPoint = try #require(
        mapper.modelPoint(for: CGPoint(x: 400.0, y: 300.0))
    )
    let drag = try #require(mapper.modelDrag(
        from: CGPoint(x: 360.0, y: 320.0),
        to: CGPoint(x: 440.0, y: 280.0)
    ))
    let expectedSpan = max(
        ruler.visibleSpanMeters,
        ruler.majorTickMeters * 20.0,
        ruler.minorTickMeters * 40.0
    )

    #expect(abs(mapper.layout.modelBounds.width - expectedSpan) < 1.0e-18)
    #expect(abs(mapper.layout.modelBounds.height - expectedSpan) < 1.0e-18)
    #expect(abs(centerPoint.x) < 1.0e-15)
    #expect(abs(centerPoint.y) < 1.0e-15)
    #expect(drag.start != drag.end)
}

@Test func viewportLayoutUnprojectsAxisFrontCanvasPlanesThroughDisplayedGridPlane() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -1.0, y: -1.0, width: 2.0, height: 2.0),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .axisFront(.z),
        verticalBounds: -1.0 ... 1.0
    )
    let worldPoint = Point3D(x: 0.12, y: 0.34, z: 0.0)
    let viewportPoint = layout.project(worldPoint)

    let unprojected = try #require(layout.displayedCanvasWorldPoint(for: viewportPoint))

    #expect(abs(unprojected.x - worldPoint.x) < 1.0e-12)
    #expect(abs(unprojected.y - worldPoint.y) < 1.0e-12)
    #expect(abs(unprojected.z - worldPoint.z) < 1.0e-12)
}

@Test func viewportLayoutUnprojectsSideAxisCanvasPlanesThroughDisplayedGridPlane() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -1.0, y: -1.0, width: 2.0, height: 2.0),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .axisFront(.x),
        verticalBounds: -1.0 ... 1.0
    )
    let worldPoint = Point3D(x: 0.0, y: -0.18, z: 0.27)
    let viewportPoint = layout.project(worldPoint)

    let unprojected = try #require(layout.displayedCanvasWorldPoint(for: viewportPoint))

    #expect(abs(unprojected.x - worldPoint.x) < 1.0e-12)
    #expect(abs(unprojected.y - worldPoint.y) < 1.0e-12)
    #expect(abs(unprojected.z - worldPoint.z) < 1.0e-12)
}

@Test func viewportModelCoordinateMapperFramesRemoteSceneWithoutOriginUnion() throws {
    var document = DesignDocument.empty()
    let ruler = WorkspaceScalePreset.sitePlanning.rulerConfiguration.normalizedForWorkspaceScale()
    _ = try document.createLineSketch(
        name: "Remote Site Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(1_000_000.0, .meter),
            y: .length(2_000_000.0, .meter)
        ),
        end: SketchPoint(
            x: .length(1_000_500.0, .meter),
            y: .length(2_000_000.0, .meter)
        )
    )
    let scene = ViewportSceneBuilder().build(document: document, ruler: ruler)
    let sceneBounds = try #require(scene.modelBounds)
    let mapper = ViewportModelCoordinateMapper(
        ruler: ruler,
        scene: scene,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let projectedSceneCenter = mapper.layout.project(CGPoint(
        x: sceneBounds.midX,
        y: sceneBounds.midY
    ))

    #expect(abs(mapper.layout.modelBounds.midX - sceneBounds.midX) < 1.0e-6)
    #expect(abs(mapper.layout.modelBounds.midY - sceneBounds.midY) < 1.0e-6)
    #expect(mapper.layout.modelBounds.minX < sceneBounds.minX)
    #expect(mapper.layout.modelBounds.maxX > sceneBounds.maxX)
    #expect(mapper.layout.modelBounds.minY < sceneBounds.minY)
    #expect(mapper.layout.modelBounds.maxY > sceneBounds.maxY)
    #expect(mapper.layout.modelBounds.minX > 0.0)
    #expect(mapper.layout.modelBounds.minY > 0.0)
    #expect(Double(mapper.layout.modelBounds.width) >= ruler.majorTickMeters * 4.0)
    #expect(Double(mapper.layout.modelBounds.height) >= ruler.majorTickMeters * 4.0)
    #expect(Double(mapper.layout.modelBounds.width) < ruler.visibleSpanMeters)
    #expect(Double(mapper.layout.modelBounds.height) < ruler.visibleSpanMeters)
    #expect(abs(projectedSceneCenter.x - 400.0) < 1.0e-6)
    #expect(abs(projectedSceneCenter.y - 300.0) < 1.0e-6)
}

@Test func viewportSceneReportsVerticalBoundsForBodyItems() {
    let bodyItem = ViewportSceneItem(
        id: "body",
        featureID: FeatureID(),
        modelBounds: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 1.0,
            sizeYMeters: 4.0,
            sizeZMeters: 1.0,
            yMinMeters: 2.0,
            yMaxMeters: 6.0
        ))
    )
    let sketchItem = ViewportSceneItem(
        id: "sketch",
        featureID: FeatureID(),
        modelBounds: CGRect(x: 4.0, y: 4.0, width: 1.0, height: 1.0),
        kind: .sketch(primitives: [])
    )
    let scene = ViewportScene(items: [bodyItem, sketchItem])

    #expect(scene.verticalBounds == 2.0 ... 6.0)
}

@Test func viewportSceneReportsZeroVerticalBoundsForSketchOnlyItems() {
    let sketchItem = ViewportSceneItem(
        id: "sketch",
        featureID: FeatureID(),
        modelBounds: CGRect(x: 4.0, y: 4.0, width: 1.0, height: 1.0),
        kind: .sketch(primitives: [])
    )

    #expect(ViewportScene(items: [sketchItem]).verticalBounds == 0.0 ... 0.0)
}

@Test func viewportLayoutUsesRenderOriginForFarCoordinateProjectionAndDepth() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: 1.0e12, y: -1.0e12, width: 10.0, height: 20.0),
        size: CGSize(width: 800.0, height: 600.0),
        verticalBounds: 1.0e12 ... (1.0e12 + 10.0)
    )
    let renderOrigin = Point3D(x: 1.0e12 + 5.0, y: 1.0e12 + 5.0, z: -1.0e12 + 10.0)
    let projectedOrigin = layout.project(renderOrigin)
    let planarPoint = CGPoint(x: 1.0e12 + 2.0, y: -1.0e12 + 6.0)
    let roundTrippedPlanarPoint = layout.unproject(layout.project(planarPoint))
    let viewNormal = try #require(layout.basis.viewNormal)
    let offsetPoint = Point3D(
        x: renderOrigin.x + 1.0,
        y: renderOrigin.y + 2.0,
        z: renderOrigin.z + 3.0
    )
    let expectedDepth = viewNormal.x + viewNormal.y * 2.0 + viewNormal.z * 3.0
    let actualDepth = try #require(layout.projectedDepth(offsetPoint))

    #expect(layout.renderOrigin == renderOrigin)
    #expect(abs(projectedOrigin.x - layout.center.x) < 1.0e-9)
    #expect(abs(projectedOrigin.y - layout.center.y) < 1.0e-9)
    #expect(abs(roundTrippedPlanarPoint.x - planarPoint.x) < 1.0e-6)
    #expect(abs(roundTrippedPlanarPoint.y - planarPoint.y) < 1.0e-6)
    #expect(abs(actualDepth - expectedDepth) < 1.0e-9)
}

@Test func viewportLayoutIncludesVerticalBoundsWhenFittingTallModels() {
    let bounds = CGRect(x: -5.0, y: -5.0, width: 10.0, height: 10.0)
    let size = CGSize(width: 800.0, height: 600.0)
    let verticalBounds = 0.0 ... 1_000.0
    let layout = ViewportLayout(
        modelBounds: bounds,
        size: size,
        verticalBounds: verticalBounds
    )
    let expectedBounds = projectedBounds(
        width: bounds.width,
        height: bounds.height,
        verticalHeight: CGFloat(verticalBounds.upperBound - verticalBounds.lowerBound),
        basis: layout.basis
    )
    let expectedScale = min(
        size.width / expectedBounds.width,
        size.height / expectedBounds.height
    )
    let projectedCorners = [
        Point3D(x: Double(bounds.minX), y: verticalBounds.lowerBound, z: Double(bounds.minY)),
        Point3D(x: Double(bounds.maxX), y: verticalBounds.lowerBound, z: Double(bounds.minY)),
        Point3D(x: Double(bounds.minX), y: verticalBounds.lowerBound, z: Double(bounds.maxY)),
        Point3D(x: Double(bounds.maxX), y: verticalBounds.lowerBound, z: Double(bounds.maxY)),
        Point3D(x: Double(bounds.minX), y: verticalBounds.upperBound, z: Double(bounds.minY)),
        Point3D(x: Double(bounds.maxX), y: verticalBounds.upperBound, z: Double(bounds.minY)),
        Point3D(x: Double(bounds.minX), y: verticalBounds.upperBound, z: Double(bounds.maxY)),
        Point3D(x: Double(bounds.maxX), y: verticalBounds.upperBound, z: Double(bounds.maxY)),
    ].map(layout.project)
    let xValues = projectedCorners.map(\.x)
    let yValues = projectedCorners.map(\.y)
    let projectedWidth = (xValues.max() ?? 0.0) - (xValues.min() ?? 0.0)
    let projectedHeight = (yValues.max() ?? 0.0) - (yValues.min() ?? 0.0)

    #expect(abs(layout.scale - expectedScale) < expectedScale * 1.0e-12)
    #expect(projectedWidth <= size.width + 1.0e-9)
    #expect(projectedHeight <= size.height + 1.0e-9)
}

@MainActor
@Test func viewportSceneProjectsZXCanvasSketchBackToCanvasCoordinates() async throws {
    let session = EditorSession()

    _ = try session.execute(
        zxCanvasRectangleSketchCommand(
            name: "ZX Canvas Rectangle",
            canvasPoint: Point2D(x: 0.03, y: 0.04)
        )
    )

    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let item = try #require(scene.items.first)

    #expect(abs(item.modelBounds.midX - 0.03) < 1.0e-12)
    #expect(abs(item.modelBounds.midY - 0.04) < 1.0e-12)
}

@MainActor
@Test func viewportMapperKeepsCanvasPointStableAfterCanvasCreation() async throws {
    let session = EditorSession()
    let size = CGSize(width: 800.0, height: 600.0)
    let clickPoint = CGPoint(x: 520.0, y: 260.0)
    let initialMapper = ViewportModelCoordinateMapper(
        document: session.document,
        ruler: session.workspaceState.ruler,
        size: size
    )
    let modelPoint = try #require(initialMapper.modelPoint(for: clickPoint))

    _ = try session.execute(
        zxCanvasRectangleSketchCommand(
            name: "ZX Canvas Rectangle",
            canvasPoint: modelPoint
        )
    )

    let finalMapper = ViewportModelCoordinateMapper(
        document: session.document,
        ruler: session.workspaceState.ruler,
        size: size
    )
    let finalPoint = finalMapper.layout.project(
        CGPoint(x: modelPoint.x, y: modelPoint.y)
    )

    #expect(abs(finalPoint.x - clickPoint.x) < 1.0e-9)
    #expect(abs(finalPoint.y - clickPoint.y) < 1.0e-9)
}

@Test func viewportCanvasDragPlaceholderUsesCoordinateAlignedFootprintOnEmptyDocument() throws {
    let document = DesignDocument.empty()
    let mapper = ViewportModelCoordinateMapper(
        document: document,
        ruler: .standard(for: .millimeter),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = try #require(mapper.modelDrag(
        from: CGPoint(x: 320.0, y: 360.0),
        to: CGPoint(x: 500.0, y: 280.0)
    ))
    let placeholder = try #require(
        ViewportCanvasDragPlaceholder(
            drag: drag,
            layout: mapper.layout
        )
    )
    let xEdge = CGVector(
        dx: placeholder.footprint.bottomRight.x - placeholder.footprint.bottomLeft.x,
        dy: placeholder.footprint.bottomRight.y - placeholder.footprint.bottomLeft.y
    )
    let yEdge = CGVector(
        dx: placeholder.footprint.topLeft.x - placeholder.footprint.bottomLeft.x,
        dy: placeholder.footprint.topLeft.y - placeholder.footprint.bottomLeft.y
    )

    #expect(placeholder.modelBounds.width > 0.0)
    #expect(placeholder.modelBounds.height > 0.0)
    #expect(isParallel(xEdge, mapper.layout.basis.xDirection))
    #expect(isParallel(yEdge, mapper.layout.basis.yDirection))
    #expect(placeholder.footprint.handlePoints.count == 8)
}

@Test func viewportCanvasDragPlaceholderAppliesWidthAndHeightOverrides() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.03, y: 0.04),
        end: Point2D(x: -0.01, y: 0.01)
    )

    let placeholder = try #require(
        ViewportCanvasDragPlaceholder(
            drag: drag,
            layout: layout,
            widthMeters: 0.05,
            heightMeters: 0.02
        )
    )
    let wrappedPreview = try #require(
        ViewportCanvasDragPreview(
            kind: .rectangle(widthMeters: 0.05, heightMeters: 0.02),
            drag: drag,
            layout: layout
        )
    )
    guard case .rectangle(let wrappedPlaceholder) = wrappedPreview else {
        Issue.record("Expected rectangle preview.")
        return
    }

    #expect(abs(placeholder.modelBounds.minX - (-0.02)) < 1.0e-12)
    #expect(abs(placeholder.modelBounds.minY - 0.02) < 1.0e-12)
    #expect(abs(placeholder.modelBounds.width - 0.05) < 1.0e-12)
    #expect(abs(placeholder.modelBounds.height - 0.02) < 1.0e-12)
    #expect(wrappedPlaceholder.modelBounds == placeholder.modelBounds)
}

@Test func viewportCanvasPolygonDragPreviewUsesToolState() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.01, y: -0.02),
        end: Point2D(x: 0.04, y: 0.02)
    )
    let state = try PolygonToolState(
        sideCount: 8,
        sizingMode: .inradius,
        inclinationMode: .horizontal
    )

    let preview = try #require(
        ViewportCanvasPolygonDragPreview(
            drag: drag,
            layout: layout,
            sideCount: state.sideCount,
            sizingMode: state.sizingMode,
            inclinationMode: state.inclinationMode
        )
    )
    let wrappedPreview = try #require(
        ViewportCanvasDragPreview(
            kind: .polygon(state, radiusMeters: nil, rotationAngleRadians: nil),
            drag: drag,
            layout: layout
        )
    )
    guard case .polygon(let wrappedPolygonPreview) = wrappedPreview else {
        Issue.record("Expected polygon preview.")
        return
    }

    let draft = try CanvasSketchCurveDrafts.polygon(
        fromCenter: drag.start,
        toRadiusPoint: drag.end,
        sides: state.sideCount,
        sizingMode: state.sizingMode,
        inclinationMode: state.inclinationMode
    )

    #expect(preview.sides == 8)
    #expect(preview.sizingMode == .inradius)
    #expect(preview.inclinationMode == .horizontal)
    #expect(preview.modelVertices == draft.vertices)
    #expect(preview.projectedVertices.count == 8)
    #expect(abs(preview.modelRadiusMeters - draft.circumradiusMeters) < 1.0e-12)
    #expect(wrappedPolygonPreview.sides == preview.sides)
    #expect(wrappedPolygonPreview.sizingMode == preview.sizingMode)
    #expect(wrappedPolygonPreview.inclinationMode == preview.inclinationMode)
}

@Test func viewportCanvasPolygonDragPreviewAppliesDimensionInputOverrides() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.01, y: -0.02),
        end: Point2D(x: 0.04, y: 0.02)
    )
    let state = try PolygonToolState(sideCount: 5)
    let angle = Double.pi / 6.0

    let preview = try #require(
        ViewportCanvasDragPreview(
            kind: .polygon(state, radiusMeters: 0.018, rotationAngleRadians: angle),
            drag: drag,
            layout: layout
        )
    )
    guard case .polygon(let polygonPreview) = preview else {
        Issue.record("Expected polygon preview.")
        return
    }

    #expect(abs(polygonPreview.sizingRadiusMeters - 0.018) < 1.0e-12)
    #expect(abs(polygonPreview.rotationAngleRadians - angle) < 1.0e-12)
}

@Test func viewportCanvasRectangleDragPreviewProjectsOntoSketchPlane() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .axisFront(.z),
        verticalBounds: -0.1 ... 0.1
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.01, y: -0.02),
        end: Point2D(x: 0.04, y: 0.03),
        sketchPlane: .xy
    )

    let placeholder = try #require(
        ViewportCanvasDragPlaceholder(drag: drag, layout: layout)
    )

    let expectedBottomLeft = layout.project(Point3D(x: 0.01, y: -0.02, z: 0.0))
    #expect(pointIsApproximatelyEqual(placeholder.footprint.bottomLeft, expectedBottomLeft))
}

@Test func viewportCanvasPolygonDragPreviewProjectsVerticesOntoSketchPlane() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .axisFront(.z),
        verticalBounds: -0.1 ... 0.1
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.0, y: 0.0),
        end: Point2D(x: 0.02, y: 0.0),
        sketchPlane: .xy
    )

    let preview = try #require(
        ViewportCanvasPolygonDragPreview(
            drag: drag,
            layout: layout,
            sideCount: 4
        )
    )
    let firstVertex = try #require(preview.modelVertices.first)
    let expectedFirstVertex = layout.project(Point3D(x: firstVertex.x, y: firstVertex.y, z: 0.0))

    #expect(pointIsApproximatelyEqual(preview.projectedVertices[0], expectedFirstVertex))
}

@Test func viewportCanvasCircleDragPreviewProjectsOntoSketchPlane() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .axisFront(.z),
        verticalBounds: -0.1 ... 0.1
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.01, y: 0.02),
        end: Point2D(x: 0.04, y: 0.02),
        sketchPlane: .xy
    )

    let preview = try #require(
        ViewportCanvasCircleDragPreview(drag: drag, layout: layout)
    )

    #expect(pointIsApproximatelyEqual(preview.projectedCenter, layout.project(Point3D(x: 0.01, y: 0.02, z: 0.0))))
    #expect(pointIsApproximatelyEqual(preview.projectedRadiusEnd, layout.project(Point3D(x: 0.04, y: 0.02, z: 0.0))))
    #expect(preview.projectedPoints.count == 49)
}

@Test func viewportPlacementPreviewGeometryBuildsToolSpecificCircle() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .axisFront(.z),
        verticalBounds: -0.1 ... 0.1
    )
    let placement = ViewportPlacementHighlight(
        point: Point2D(x: 0.01, y: 0.02),
        sketchPlane: .xy,
        previewKind: .circle(radiusMeters: 0.03)
    )

    let geometry = try #require(
        ViewportPlacementPreviewGeometry(
            placement: placement,
            layout: layout,
            defaults: .standard,
            visibleCellMeters: 0.01
        )
    )

    guard case .circle(let center, let points, let radiusEnd) = geometry.shape else {
        Issue.record("Expected circle placement preview.")
        return
    }
    #expect(pointIsApproximatelyEqual(center, layout.project(Point3D(x: 0.01, y: 0.02, z: 0.0))))
    #expect(pointIsApproximatelyEqual(radiusEnd, layout.project(Point3D(x: 0.04, y: 0.02, z: 0.0))))
    #expect(points.count == 49)
}

@Test func viewportPlacementPreviewGeometryUsesVisibleCellForSolidRectangle() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0),
        basis: .axisFront(.z),
        verticalBounds: -0.1 ... 0.1
    )
    let placement = ViewportPlacementHighlight(
        point: Point2D(x: 0.0, y: 0.0),
        sketchPlane: .xy,
        previewKind: .rectangle(widthMeters: nil, heightMeters: nil, fallback: .visibleCell)
    )

    let geometry = try #require(
        ViewportPlacementPreviewGeometry(
            placement: placement,
            layout: layout,
            defaults: .standard,
            visibleCellMeters: 0.04
        )
    )

    guard case .rectangle(let footprint) = geometry.shape else {
        Issue.record("Expected rectangle placement preview.")
        return
    }
    #expect(pointIsApproximatelyEqual(footprint.bottomLeft, layout.project(Point3D(x: -0.02, y: -0.02, z: 0.0))))
    #expect(pointIsApproximatelyEqual(footprint.topRight, layout.project(Point3D(x: 0.02, y: 0.02, z: 0.0))))
}

@Test func viewportModelDragAppliesSketchAxisConstraint() {
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.01, y: -0.02),
        end: Point2D(x: 0.04, y: 0.03),
        sketchPlane: .yz,
        startWorldPoint: Point3D(x: 0.0, y: 0.01, z: -0.02),
        endWorldPoint: Point3D(x: 0.0, y: 0.04, z: 0.03),
        startViewRayAnchorWorldPoint: Point3D(x: 0.12, y: 0.01, z: -0.02),
        endViewRayAnchorWorldPoint: Point3D(x: 0.12, y: 0.04, z: 0.03)
    )

    let constrained = drag.constrained(by: .z)

    #expect(constrained.start == drag.start)
    #expect(abs(constrained.end.x - 0.01) < 1.0e-12)
    #expect(abs(constrained.end.y - 0.03) < 1.0e-12)
    #expect(constrained.sketchPlane == .yz)
    #expect(constrained.startWorldPoint == drag.startWorldPoint)
    #expect(constrained.endWorldPoint == nil)
    #expect(constrained.startViewRayAnchorWorldPoint == drag.startViewRayAnchorWorldPoint)
    #expect(constrained.endViewRayAnchorWorldPoint == nil)
}

@Test func viewportCanvasDragSnapResolverAppliesGridBeforeAxisConstraint() {
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.012, y: 0.018),
        end: Point2D(x: 0.026, y: 0.037),
        sketchPlane: .xy
    )
    let options = SnapResolutionOptions(
        usesGrid: true,
        usesObjects: false,
        gridIntervalMeters: 0.01
    )

    let resolved = ViewportCanvasDragSnapResolver().resolvedDrag(
        drag,
        document: .empty(),
        ruler: .standard(for: .millimeter),
        snapOptions: options,
        axisConstraint: .x
    )

    #expect(pointIsApproximatelyEqual(resolved.start, Point2D(x: 0.01, y: 0.02)))
    #expect(pointIsApproximatelyEqual(resolved.end, Point2D(x: 0.03, y: 0.02)))
}

@Test func viewportCanvasDragSnapResolverKeepsAxisConstraintWhenSnapDisabled() {
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.012, y: 0.018),
        end: Point2D(x: 0.026, y: 0.037),
        sketchPlane: .xy,
        startWorldPoint: Point3D(x: 0.012, y: 0.018, z: 0.0),
        endWorldPoint: Point3D(x: 0.026, y: 0.037, z: 0.0),
        startViewRayAnchorWorldPoint: Point3D(x: 0.012, y: 0.018, z: 0.1),
        endViewRayAnchorWorldPoint: Point3D(x: 0.026, y: 0.037, z: 0.1)
    )
    let options = SnapResolutionOptions(
        usesGrid: false,
        usesObjects: false
    )

    let resolved = ViewportCanvasDragSnapResolver().resolvedDrag(
        drag,
        document: .empty(),
        ruler: .standard(for: .millimeter),
        snapOptions: options,
        axisConstraint: .x
    )

    #expect(pointIsApproximatelyEqual(resolved.start, drag.start))
    #expect(pointIsApproximatelyEqual(resolved.end, Point2D(x: drag.end.x, y: drag.start.y)))
    #expect(resolved.startWorldPoint == drag.startWorldPoint)
    #expect(resolved.endWorldPoint == nil)
    #expect(resolved.startViewRayAnchorWorldPoint == nil)
    #expect(resolved.endViewRayAnchorWorldPoint == nil)
}

@Test func viewportCanvasDragSnapResolverResolvesCustomPlaneWorldPointsAfterGridSnap() throws {
    let plane = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 2.0, y: 3.0, z: 4.0),
            normal: .unitY
        )
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.012, y: 0.018),
        end: Point2D(x: 0.026, y: 0.037),
        sketchPlane: plane,
        startWorldPoint: Point3D(x: 2.012, y: 3.0, z: 4.018),
        endWorldPoint: Point3D(x: 2.026, y: 3.0, z: 4.037)
    )
    let options = SnapResolutionOptions(
        usesGrid: true,
        usesObjects: false,
        gridIntervalMeters: 0.01
    )

    let resolved = ViewportCanvasDragSnapResolver().resolvedDrag(
        drag,
        document: .empty(),
        ruler: .standard(for: .millimeter),
        snapOptions: options,
        axisConstraint: .x
    )
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)

    #expect(pointIsApproximatelyEqual(resolved.start, Point2D(x: 0.01, y: 0.02)))
    #expect(pointIsApproximatelyEqual(resolved.end, Point2D(x: 0.03, y: 0.02)))
    #expect(resolved.startWorldPoint == coordinateSystem.point(from: resolved.start))
    #expect(resolved.endWorldPoint == coordinateSystem.point(from: resolved.end))
}

@Test func viewportCanvasDragSnapResolverReportsFailuresWithoutChangingFallbackDrag() {
    let drag = ViewportModelDrag(
        start: Point2D(x: .nan, y: 0.018),
        end: Point2D(x: 0.026, y: 0.037),
        sketchPlane: .xy
    )
    let options = SnapResolutionOptions(
        usesGrid: true,
        usesObjects: false,
        gridIntervalMeters: 0.01
    )

    let resolution = ViewportCanvasDragSnapResolver().resolution(
        drag,
        document: .empty(),
        ruler: .standard(for: .millimeter),
        snapOptions: options,
        axisConstraint: .x
    )

    #expect(resolution.startResolution.attemptedResolution)
    #expect(resolution.startResolution.failureDescription != nil)
    #expect(resolution.endResolution.attemptedResolution)
    #expect(!resolution.failureDescriptions.isEmpty)
    #expect(resolution.drag.start.x.isNaN)
    #expect(resolution.drag.start.y == drag.start.y)
}

@Test func viewportSnapResolutionOptionsUsesSharedAvailabilityContract() {
    let disabled = SnapResolutionOptions(
        usesGrid: false,
        usesObjects: false
    )
    let constructionPlaneOnly = SnapResolutionOptions(
        usesGrid: false,
        usesObjects: false,
        constructionPlane: .xy
    )

    #expect(!disabled.shouldResolve())
    #expect(disabled.shouldResolve(for: ViewportInputModifierFlags(containsControl: true)))
    #expect(constructionPlaneOnly.shouldResolve())
}

@Test func viewportCanvasArcDragPreviewUsesSharedCurveConstruction() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.01, y: -0.02),
        end: Point2D(x: 0.04, y: 0.02)
    )

    let preview = try #require(
        ViewportCanvasArcDragPreview(drag: drag, layout: layout)
    )
    let wrappedPreview = try #require(
        ViewportCanvasDragPreview(
            kind: .arc(radiusMeters: nil, spanAngleRadians: nil),
            drag: drag,
            layout: layout
        )
    )
    guard case .arc = wrappedPreview else {
        Issue.record("Expected arc preview.")
        return
    }

    let draft = try CanvasSketchCurveDrafts.arc(
        fromCenter: drag.start,
        toRadiusPoint: drag.end
    )
    #expect(preview.modelCenter == CGPoint(x: draft.center.x, y: draft.center.y))
    #expect(abs(preview.modelRadiusMeters - draft.radiusMeters) < 1.0e-12)
    #expect(abs(preview.startAngleRadians - draft.startAngleRadians) < 1.0e-12)
    #expect(abs(preview.endAngleRadians - draft.endAngleRadians) < 1.0e-12)
    #expect(preview.projectedPoints.count == 25)
    #expect(preview.modelBounds.width > 0.0)
    #expect(preview.modelBounds.height > 0.0)
}

@Test func viewportCanvasArcDragPreviewAppliesDimensionInputOverrides() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.01, y: -0.02),
        end: Point2D(x: 0.04, y: 0.02)
    )
    let span = Double.pi / 3.0

    let preview = try #require(
        ViewportCanvasArcDragPreview(
            drag: drag,
            layout: layout,
            radiusMeters: 0.017,
            spanAngleRadians: span
        )
    )

    #expect(abs(preview.modelRadiusMeters - 0.017) < 1.0e-12)
    #expect(abs((preview.endAngleRadians - preview.startAngleRadians) - span) < 1.0e-12)
}

@Test func viewportCanvasSplineDragPreviewUsesSharedCurveConstruction() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.0, y: 0.0),
        end: Point2D(x: 0.03, y: 0.04)
    )

    let preview = try #require(
        ViewportCanvasSplineDragPreview(drag: drag, layout: layout)
    )
    let wrappedPreview = try #require(
        ViewportCanvasDragPreview(kind: .spline, drag: drag, layout: layout)
    )
    guard case .spline = wrappedPreview else {
        Issue.record("Expected spline preview.")
        return
    }

    let draft = try CanvasSketchCurveDrafts.spline(
        from: drag.start,
        to: drag.end
    )

    #expect(preview.modelControlPoints == draft.controlPoints)
    #expect(preview.projectedControlPoints.count == 4)
    #expect(preview.projectedCurvePoints.count == 33)
    #expect(preview.modelBounds.width > 0.0)
    #expect(preview.modelBounds.height > 0.0)
}

@Test func viewportCameraZoomPolicyExpandsForSitePlanningScale() throws {
    let document = DesignDocument.empty()
    let ruler = WorkspaceScalePreset.sitePlanning.rulerConfiguration
    let size = CGSize(width: 800.0, height: 600.0)
    let identityLayout = ViewportModelCoordinateMapper(
        document: document,
        ruler: ruler,
        size: size
    ).layout
    let maximumZoom = ViewportCameraZoomPolicy.maximumZoom(
        ruler: ruler,
        identityScale: identityLayout.scale
    )
    let zoomedLayout = ViewportModelCoordinateMapper(
        document: document,
        ruler: ruler,
        size: size,
        camera: ViewportCamera(zoom: maximumZoom * 2.0)
    ).layout
    let minorTickPixels = CGFloat(ruler.minorTickMeters) * zoomedLayout.scale
    let meterPixels = zoomedLayout.scale

    #expect(maximumZoom > ViewportCamera.maximumZoom)
    #expect(identityLayout.maximumZoom == maximumZoom)
    #expect(minorTickPixels >= ViewportCameraZoomPolicy.targetMinorTickPixels - 0.001)
    #expect(meterPixels >= ViewportCameraZoomPolicy.targetMinorTickPixels - 0.001)
}

/// The canvas draws the axis triad and nothing else, so the top edge is the
/// grid's: no rectangle is withheld from the pointer there and no fitting
/// inset is taken from it. The scale readout the badge used to carry now has
/// a seat in the canvas header, above the canvas rather than over it.
@MainActor
@Test func viewportCanvasChromeLeavesTheTopEdgeToTheGrid() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(viewportSize: viewportSize)

    #expect(layout.inputExclusionRects == [layout.axisControlExclusionRect])
    #expect(layout.fittingInsets.top == 0.0)
    #expect(!layout.containsCanvasChrome(CGPoint(x: 12.0, y: 12.0)))
    #expect(!layout.intersectsCanvasChrome(CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: 30.0)))
    #expect(ViewportCanvasChromeMetrics.topControlContentHeight < ViewportCanvasChromeMetrics.topControlHeight)
    #expect(
        ViewportCanvasChromeMetrics.topControlDividerHeight
            <= ViewportCanvasChromeMetrics.topControlContentHeight
    )
    #expect(ViewportCanvasChromeMetrics.topControlHorizontalPadding == ViewportCanvasChromeMetrics.edgePadding)
    #expect(ViewportCanvasChromeMetrics.topControlItemSpacing <= ViewportCanvasChromeMetrics.edgePadding)
    #expect(ViewportCanvasChromeMetrics.borderWidth == 0.0)
    #expect(ViewportCanvasChromeMetrics.borderOpacity == 0.0)
}

@MainActor
@Test func viewportAxisTriadUsesCompactBottomCenterInputExclusion() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(viewportSize: viewportSize)
    let rect = layout.axisControlExclusionRect

    #expect(ViewportCanvasChromeLayout.axisControlSize.height <= 44.0)
    #expect(abs(rect.midX - viewportSize.width / 2.0) < 1.0e-9)
    #expect(rect.minY > viewportSize.height * 0.80)
    #expect(rect.width > ViewportCanvasChromeLayout.axisControlSize.width)
    #expect(rect.height > ViewportCanvasChromeLayout.axisControlSize.height)
    #expect(rect.contains(CGPoint(x: viewportSize.width / 2.0, y: viewportSize.height - 24.0)))
    #expect(layout.inputExclusionRects.count == 1)
    #expect(!layout.containsCanvasChrome(CGPoint(x: 20.0, y: 20.0)))
    #expect(!layout.containsCanvasChrome(CGPoint(x: viewportSize.width / 2.0, y: viewportSize.height / 2.0)))
}

@MainActor
@Test func viewportCanvasChromeLayoutDetectsScaleLabelOverlap() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(viewportSize: viewportSize)
    let topLabelRect = CGRect(x: 12.0, y: 12.0, width: 80.0, height: 16.0)
    let centerLabelRect = CGRect(x: 360.0, y: 292.0, width: 80.0, height: 16.0)

    #expect(!layout.intersectsCanvasChrome(topLabelRect))
    #expect(layout.intersectsCanvasChrome(layout.axisControlRect))
    #expect(!layout.intersectsCanvasChrome(centerLabelRect))
}

@MainActor
@Test func viewportCanvasChromeLayoutMergesExternalOverlayExclusions() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let overlayRect = CGRect(x: 612.0, y: 44.0, width: 38.0, height: 210.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        additionalExclusions: [
            ViewportCanvasOverlayExclusion(rect: overlayRect, fittingEdges: []),
        ]
    )

    #expect(layout.inputExclusionRects.count == 2)
    #expect(layout.containsCanvasChrome(CGPoint(x: overlayRect.midX, y: overlayRect.midY)))
    #expect(layout.containsCanvasChrome(CGPoint(
        x: overlayRect.minX - ViewportCanvasChromeLayout.inputExclusionPadding / 2.0,
        y: overlayRect.midY
    )))
    #expect(!layout.containsCanvasChrome(CGPoint(
        x: overlayRect.minX - ViewportCanvasChromeLayout.inputExclusionPadding - 2.0,
        y: overlayRect.midY
    )))
    #expect(layout.intersectsCanvasChrome(overlayRect))
    #expect(layout.fittingInsets.leading == 0.0)
    #expect(layout.fittingInsets.trailing == 0.0)
}

@MainActor
@Test func viewportCanvasChromeLayoutIgnoresNonFiniteOverlayExclusions() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        additionalExclusions: [
            ViewportCanvasOverlayExclusion(
                rect: CGRect(x: CGFloat.nan, y: 0.0, width: 48.0, height: 600.0),
                fittingEdges: .leading
            ),
            ViewportCanvasOverlayExclusion(
                rect: CGRect(x: 700.0, y: 0.0, width: CGFloat.infinity, height: 600.0),
                fittingEdges: .trailing
            ),
        ]
    )
    let insets = layout.fittingInsets

    #expect(layout.inputExclusionRects.count == 1)
    #expect(insets.top == 0.0)
    #expect(insets.leading == 0.0)
    #expect(insets.trailing == 0.0)
    #expect(insets.bottom == viewportSize.height - layout.axisControlExclusionRect.minY)
}

@MainActor
@Test func viewportCanvasChromeLayoutPlacesSnapLabelsAwayFromOverlayChrome() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let rightOverlayRect = CGRect(x: 700.0, y: 0.0, width: 100.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        additionalExclusions: [
            ViewportCanvasOverlayExclusion(rect: rightOverlayRect, fittingEdges: .trailing),
        ]
    )
    let labelRect = layout.snapLabelRect(
        near: CGPoint(x: 690.0, y: 120.0),
        size: CGSize(width: 72.0, height: 20.0)
    )

    #expect(labelRect.maxX < rightOverlayRect.minX)
    #expect(!layout.intersectsCanvasChrome(labelRect))
    #expect(labelRect.minX >= 0.0)
    #expect(labelRect.maxX <= viewportSize.width)
    #expect(labelRect.minY >= 0.0)
    #expect(labelRect.maxY <= viewportSize.height)
}

@MainActor
@Test func viewportAxisTriadReservesBottomOverlayHeight() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let reservedHeight: CGFloat = 48.0
    let baseline = ViewportCanvasChromeLayout(viewportSize: viewportSize)
    let reserved = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        bottomReservedHeight: reservedHeight
    )

    #expect(reserved.axisControlRect.minY == baseline.axisControlRect.minY - reservedHeight)
    #expect(reserved.axisControlExclusionRect.minY == baseline.axisControlExclusionRect.minY - reservedHeight)
    #expect(reserved.inputExclusionRects.count == baseline.inputExclusionRects.count)
    #expect(!reserved.axisControlExclusionRect.contains(CGPoint(
        x: viewportSize.width / 2.0,
        y: viewportSize.height - 24.0
    )))
    #expect(reserved.axisControlExclusionRect.contains(CGPoint(
        x: viewportSize.width / 2.0,
        y: viewportSize.height - reservedHeight - 24.0
    )))
}

@MainActor
@Test func viewportCanvasChromeLayoutReportsCompactFittingInsets() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(viewportSize: viewportSize)
    let insets = layout.fittingInsets

    #expect(insets.top == 0.0)
    #expect(insets.bottom == viewportSize.height - layout.axisControlExclusionRect.minY)
    #expect(insets.leading == 0.0)
    #expect(insets.trailing == 0.0)
}

@MainActor
@Test func viewportCanvasChromeLayoutReportsEdgePanelFittingInsets() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let leadingPanel = CGRect(x: 0.0, y: 90.0, width: 48.0, height: 360.0)
    let trailingPanel = CGRect(x: 760.0, y: 90.0, width: 40.0, height: 360.0)
    let bottomPanel = CGRect(x: 0.0, y: 540.0, width: 800.0, height: 60.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        additionalExclusions: [
            ViewportCanvasOverlayExclusion(rect: leadingPanel, fittingEdges: .leading),
            ViewportCanvasOverlayExclusion(rect: trailingPanel, fittingEdges: .trailing),
            ViewportCanvasOverlayExclusion(rect: bottomPanel, fittingEdges: .bottom),
        ]
    )
    let insets = layout.fittingInsets

    #expect(insets.top == 0.0)
    #expect(insets.leading == leadingPanel.width + ViewportCanvasChromeLayout.inputExclusionPadding)
    #expect(insets.trailing == trailingPanel.width + ViewportCanvasChromeLayout.inputExclusionPadding)
    #expect(insets.bottom == bottomPanel.height + ViewportCanvasChromeLayout.inputExclusionPadding)
}

@MainActor
@Test func viewportInputSurfaceClearsInteractionStateOnChromeHitTest() {
    let view = ViewportInputSurface.InputView(frame: CGRect(
        x: 0.0,
        y: 0.0,
        width: 800.0,
        height: 600.0
    ))
    var clearedHover = false
    var clearedDragPreview = false
    view.inputExclusionRects = [CGRect(x: 10.0, y: 10.0, width: 100.0, height: 40.0)]
    view.onHover = { point, _ in
        if point == nil {
            clearedHover = true
        }
    }
    view.onDragPreview = { start, current, _ in
        if start == nil && current == nil {
            clearedDragPreview = true
        }
    }

    let hit = view.hitTest(CGPoint(x: 20.0, y: 20.0))

    #expect(hit == nil)
    #expect(clearedHover)
    #expect(clearedDragPreview)
}

@MainActor
@Test func viewportInputSurfaceSuppressesRepeatedChromeClearCallbacks() {
    let view = ViewportInputSurface.InputView(frame: CGRect(
        x: 0.0,
        y: 0.0,
        width: 800.0,
        height: 600.0
    ))
    var hoverClearCount = 0
    var dragPreviewClearCount = 0
    view.inputExclusionRects = [CGRect(x: 10.0, y: 10.0, width: 100.0, height: 40.0)]
    view.onHover = { point, _ in
        if point == nil {
            hoverClearCount += 1
        }
    }
    view.onDragPreview = { start, current, _ in
        if start == nil && current == nil {
            dragPreviewClearCount += 1
        }
    }

    _ = view.hitTest(CGPoint(x: 20.0, y: 20.0))
    _ = view.hitTest(CGPoint(x: 30.0, y: 20.0))
    _ = view.hitTest(CGPoint(x: 40.0, y: 20.0))

    #expect(hoverClearCount == 1)
    #expect(dragPreviewClearCount == 1)
}

@MainActor
@Test func viewportInputSurfaceClearsInteractionStateWhenExclusionMovesUnderTrackedPointer() {
    let view = ViewportInputSurface.InputView(frame: CGRect(
        x: 0.0,
        y: 0.0,
        width: 800.0,
        height: 600.0
    ))
    var hoverClearCount = 0
    var dragPreviewClearCount = 0
    view.onHover = { point, _ in
        if point == nil {
            hoverClearCount += 1
        }
    }
    view.onDragPreview = { start, current, _ in
        if start == nil && current == nil {
            dragPreviewClearCount += 1
        }
    }

    _ = view.hitTest(CGPoint(x: 240.0, y: 160.0))
    view.inputExclusionRects = [CGRect(x: 200.0, y: 120.0, width: 120.0, height: 80.0)]

    #expect(hoverClearCount == 1)
    #expect(dragPreviewClearCount == 1)
}

@MainActor
@Test func viewportInputSurfaceKeepsInteractionStateWhenExclusionUpdatesAwayFromTrackedPointer() {
    let view = ViewportInputSurface.InputView(frame: CGRect(
        x: 0.0,
        y: 0.0,
        width: 800.0,
        height: 600.0
    ))
    var hoverClearCount = 0
    view.onHover = { point, _ in
        if point == nil {
            hoverClearCount += 1
        }
    }

    _ = view.hitTest(CGPoint(x: 240.0, y: 160.0))
    view.inputExclusionRects = [CGRect(x: 10.0, y: 10.0, width: 100.0, height: 40.0)]

    #expect(hoverClearCount == 0)
}

@Test func viewportSnapOverlayPolicySuppressesPassiveGridLabels() {
    let passiveHover = ViewportSnapOverlayContext.passiveHover
    let creationDrag = ViewportSnapOverlayContext.creationDrag
    let activeCreationDrag = ViewportActiveDrag(
        startLocation: .zero,
        currentLocation: CGPoint(x: 10.0, y: 10.0),
        kind: .creation(.rectangle(widthMeters: nil, heightMeters: nil))
    )
    let activeSelectionDrag = ViewportActiveDrag(
        startLocation: .zero,
        currentLocation: CGPoint(x: 10.0, y: 10.0),
        kind: .selection
    )

    #expect(ViewportSnapOverlayContext(activeCanvasDrag: activeCreationDrag) == .creationDrag)
    #expect(ViewportSnapOverlayContext(activeCanvasDrag: activeSelectionDrag) == .passiveHover)
    #expect(!ViewportSnapOverlayPolicy.drawsOverlay(kind: .grid, context: passiveHover))
    #expect(ViewportSnapOverlayPolicy.drawsOverlay(kind: .grid, context: creationDrag))
    #expect(!ViewportSnapOverlayPolicy.drawsLabel(kind: .grid, context: creationDrag))
    #expect(ViewportSnapOverlayPolicy.drawsOverlay(kind: .lineStart, context: passiveHover))
    #expect(ViewportSnapOverlayPolicy.drawsLabel(kind: .lineStart, context: passiveHover))
    #expect(ViewportSnapOverlayPolicy.publishedKind(.grid, context: passiveHover) == nil)
    #expect(ViewportSnapOverlayPolicy.publishedKind(.lineStart, context: passiveHover) == .lineStart)
}

@Test func viewportSnapResolutionServiceResolvesInputOutsideDrawing() {
    let options = SnapResolutionOptions(
        usesGrid: true,
        usesObjects: false,
        gridIntervalMeters: 0.01
    )
    let resolution = ViewportSnapResolutionService().resolution(
        for: ViewportSnapQuery(
            point: Point2D(x: 0.012, y: 0.018),
            referencePoint: nil
        ),
        document: .empty(),
        ruler: .standard(for: .millimeter),
        options: options,
        modifierFlags: ViewportInputModifierFlags()
    )

    #expect(resolution.failureDescription == nil)
    #expect(resolution.attemptedResolution)
    #expect(resolution.result?.selectedCandidate?.kind == .grid)
    #expect(pointIsApproximatelyEqual(
        resolution.result?.resolvedPoint ?? Point2D(x: 0.0, y: 0.0),
        Point2D(x: 0.01, y: 0.02)
    ))
    #expect(resolution.publishedKind(context: .passiveHover) == nil)
    #expect(resolution.publishedKind(context: .creationDrag) == .grid)
}

@Test func viewportSnapResolutionServiceClearsWhenQueryIsUnavailable() {
    let resolution = ViewportSnapResolutionService().resolution(
        for: nil,
        document: .empty(),
        ruler: .standard(for: .millimeter),
        options: SnapResolutionOptions(),
        modifierFlags: ViewportInputModifierFlags()
    )

    #expect(resolution.result == nil)
    #expect(resolution.failureDescription == nil)
    #expect(!resolution.attemptedResolution)
    #expect(resolution.publishedKind(context: .creationDrag) == nil)
}

@Test func viewportSnapResolutionServiceReportsResolutionFailures() {
    let resolution = ViewportSnapResolutionService().resolution(
        for: ViewportSnapQuery(
            point: Point2D(x: .nan, y: 0.0),
            referencePoint: nil
        ),
        document: .empty(),
        ruler: .standard(for: .millimeter),
        options: SnapResolutionOptions(),
        modifierFlags: ViewportInputModifierFlags()
    )

    #expect(resolution.result == nil)
    #expect(resolution.failureDescription != nil)
    #expect(resolution.attemptedResolution)
}


@MainActor
private func makeCurvedSweepViewportSession() throws -> (
    session: EditorSession,
    profileID: FeatureID,
    commandResult: CommandExecutionResult
) {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Viewport Curved Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createArcSketch(
        name: "Viewport Curved Sweep Path",
        plane: .yz,
        center: SketchPoint(
            x: .length(60.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(60.0, .millimeter),
        // The exact circular path-normal sweep requires the path start to lie
        // on the section plane, so the arc starts at the profile origin and
        // curves away from the plane.
        startAngle: .angle(180.0, .degree),
        endAngle: .angle(270.0, .degree)
    )
    let session = EditorSession(document: document)
    let result = try session.execute(.createSweep(
        name: "Viewport Curved Sweep",
        sections: [.profile(ProfileReference(featureID: profileID))],
        path: SweepPathReference(featureID: pathID),
        guides: [],
        targets: [],
        options: SweepOptions()
    ))
    return (session, profileID, result)
}

private func projectedCenter(
    of points: [Point3D],
    layout: ViewportLayout
) -> CGPoint {
    let projectedPoints = points.map { layout.project($0) }
    let sum = projectedPoints.reduce(CGPoint.zero) { partial, point in
        CGPoint(x: partial.x + point.x, y: partial.y + point.y)
    }
    let count = max(CGFloat(projectedPoints.count), 1.0)
    return CGPoint(x: sum.x / count, y: sum.y / count)
}

private func viewportSceneIgnoringEvaluationLocalBodyIDs(_ scene: ViewportScene) -> ViewportScene {
    ViewportScene(items: scene.items.map { item in
        guard case .body(var component) = item.kind else {
            return item
        }
        component.bodyID = nil
        var normalizedItem = item
        normalizedItem.kind = .body(component: component)
        return normalizedItem
    })
}

private func modelBounds(for points: [Point3D]) -> CGRect {
    let xValues = points.map(\.x)
    let zValues = points.map(\.z)
    let minX = xValues.min() ?? 0.0
    let maxX = xValues.max() ?? 0.001
    let minZ = zValues.min() ?? 0.0
    let maxZ = zValues.max() ?? 0.001
    return CGRect(
        x: minX,
        y: minZ,
        width: max(maxX - minX, 1.0e-9),
        height: max(maxZ - minZ, 1.0e-9)
    )
}

private func projectedBounds(
    width: CGFloat,
    height: CGFloat,
    verticalHeight: CGFloat = 0.0,
    basis: ViewportProjectionBasis
) -> CGRect {
    var points: [CGPoint] = []
    points.reserveCapacity(8)
    for x in [CGFloat(0.0), width] {
        for y in [CGFloat(0.0), verticalHeight] {
            for z in [CGFloat(0.0), height] {
                points.append(CGPoint(
                    x: basis.xDirection.dx * x
                        + basis.yDirection.dx * y
                        + basis.zDirection.dx * z,
                    y: basis.xDirection.dy * x
                        + basis.yDirection.dy * y
                        + basis.zDirection.dy * z
                ))
            }
        }
    }
    let minX = points.map(\.x).min() ?? 0.0
    let minY = points.map(\.y).min() ?? 0.0
    let maxX = points.map(\.x).max() ?? 0.0
    let maxY = points.map(\.y).max() ?? 0.0
    return CGRect(
        x: minX,
        y: minY,
        width: maxX - minX,
        height: maxY - minY
    )
}

private func center(of points: [CGPoint]) -> CGPoint {
    let sum = points.reduce(CGPoint.zero) { partial, point in
        CGPoint(x: partial.x + point.x, y: partial.y + point.y)
    }
    let count = max(CGFloat(points.count), 1.0)
    return CGPoint(x: sum.x / count, y: sum.y / count)
}

private func bodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { entry in
        entry.value.reference?.kind == .body && entry.value.reference?.featureID == featureID
    }?.key
}

private func sceneSubtreeIDs(
    rootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) -> [SceneNodeID] {
    var result: [SceneNodeID] = []
    var visited: Set<SceneNodeID> = []
    appendSceneSubtreeIDs(
        rootSceneNodeID,
        document: document,
        visited: &visited,
        result: &result
    )
    return result
}

private func appendSceneSubtreeIDs(
    _ sceneNodeID: SceneNodeID,
    document: DesignDocument,
    visited: inout Set<SceneNodeID>,
    result: inout [SceneNodeID]
) {
    guard visited.insert(sceneNodeID).inserted,
          let node = document.productMetadata.sceneNodes[sceneNodeID] else {
        return
    }
    result.append(sceneNodeID)
    for childID in node.childIDs {
        appendSceneSubtreeIDs(
            childID,
            document: document,
            visited: &visited,
            result: &result
        )
    }
}

private func translationTransform(
    x: Double,
    y: Double,
    z: Double
) throws -> Transform3D {
    Transform3D(matrix: try Matrix4x4(values: [
        1.0, 0.0, 0.0, x,
        0.0, 1.0, 0.0, y,
        0.0, 0.0, 1.0, z,
        0.0, 0.0, 0.0, 1.0,
    ]))
}

private func viewportSurfaceContinuityPatchNetworkMesh(centerZ: Double) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.01, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.01, z: 0.0),
            Point3D(x: 0.01, y: 0.01, z: centerZ),
            Point3D(x: 0.02, y: 0.01, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}

private func viewportSurfaceAnalysisSingleQuadMesh(topRightZ: Double) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: topRightZ),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}

private func viewportDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
}

private func viewportEditableDirectBSplineSurface() -> BSplineSurface3D {
    let baseSurface = viewportDirectBSplineSurface()
    return BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: baseSurface.controlPoints
    )
}

private func viewportSceneOverlayState(
    from workspaceState: WorkspaceState
) -> ViewportSceneOverlayState {
    ViewportSceneOverlayState(
        curveCurvatureDisplays: workspaceState.curveCurvatureDisplays,
        pointDisplays: workspaceState.pointDisplays,
        surfaceControlPointDisplays: workspaceState.surfaceControlPointDisplays,
        surfaceFrameDisplays: workspaceState.surfaceFrameDisplays
    )
}

private func pointIsApproximatelyEqual(
    _ lhs: Point2D,
    _ rhs: Point2D,
    tolerance: Double = 1.0e-12
) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

private func pointIsApproximatelyEqual(
    _ lhs: CGPoint,
    _ rhs: CGPoint,
    tolerance: CGFloat = 1.0e-9
) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}


/// Shared feature identity so equal role strings map to equal subshape IDs
/// within this file's tests.
private let generatedTopologyTestFeatureID = FeatureID()

private func generatedTopologyTestSubshapeID(_ role: String) -> SubshapeID {
    SubshapeID(
        featureID: generatedTopologyTestFeatureID,
        role: role,
        ordinal: 0
    )
}

/// Builds the rectangle sketch a canvas click places on the ZX construction
/// plane, so viewport projection tests stay independent of the planning layer.
private func zxCanvasRectangleSketchCommand(
    name: String,
    canvasPoint: Point2D,
    halfSideMeters: Double = 0.02
) -> EditorCommand {
    let center = SketchPlaneCanvasMapper(sketchPlane: .zx).localPoint(fromCanvas: canvasPoint)
    return .createRectangleSketchFromCorners(
        name: name,
        plane: .zx,
        firstCorner: SketchPoint(
            x: .length(center.x - halfSideMeters, .meter),
            y: .length(center.y - halfSideMeters, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(center.x + halfSideMeters, .meter),
            y: .length(center.y + halfSideMeters, .meter)
        )
    )
}

// MARK: - Declared sketch display resolution

/// The segments a built sketch primitive is divided into, resolved from the sketch
/// object's declared subdivisions. `RupaViewportScene/DESIGN.md` owns the placement.
@MainActor
private func builtCircleSegmentCount(in session: EditorSession) throws -> Int {
    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: session.workspaceState.ruler
    )
    for item in scene.items {
        guard case .sketch(let primitives) = item.kind else { continue }
        for primitive in primitives {
            if case .circle(_, _, _, let segmentCount) = primitive {
                return segmentCount
            }
        }
    }
    throw EditorError(code: .commandInvalid, message: "No circle primitive was built.")
}

@MainActor
@Test func aCircleSketchIsDrawnAtTheSubdivisionCountItsOwnSchemaDeclares() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Declared Circle",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
            radius: .length(10.0, .millimeter)
        )
    )

    #expect(try builtCircleSegmentCount(in: session) == 64)
}

@MainActor
@Test func editingACircleSketchSubdivisionCountChangesWhatTheFrameDraws() async throws {
    let session = EditorSession()
    let result = try session.execute(
        .createCircleSketch(
            name: "Edited Circle",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
            radius: .length(10.0, .millimeter)
        )
    )
    let featureID = try #require(result.primaryFeatureID)
    let nodeID = try #require(session.document.productMetadata.sceneNodes.first { _, node in
        node.reference == .sketch(featureID)
    }?.key)
    _ = try session.execute(
        .setSceneNodeObjectProperty(
            id: nodeID,
            propertyID: PropertyID("sides.x"),
            value: .integer(16)
        )
    )

    #expect(try builtCircleSegmentCount(in: session) == 16)
}

@MainActor
@Test func anArcSketchDeclaringNoCountIsDrawnAtTheFramesOwnResolution() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Undeclared Arc",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )

    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: session.workspaceState.ruler
    )
    let counts: [Int] = scene.items.flatMap { item -> [Int] in
        guard case .sketch(let primitives) = item.kind else { return [] }
        return primitives.compactMap { primitive in
            if case .arc(_, _, _, _, _, let segmentCount) = primitive {
                return segmentCount
            }
            return nil
        }
    }

    #expect(counts == [24])
}
