import AppKit
import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

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

    let scene = ViewportSceneBuilder().build(document: session.document)

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

    let scene = ViewportSceneBuilder().build(document: session.document)

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
    try document.setRulerConfiguration(WorkspaceScalePreset.microFabrication.rulerConfiguration)
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

    let scene = ViewportSceneBuilder().build(document: document)
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

    let scene = ViewportSceneBuilder().build(document: session.document)
    let baseBody = try #require(scene.items.first { item in
        item.componentInstanceID == nil && item.featureID == bodyFeatureID
    })
    let instanceItems = scene.items
        .filter { $0.componentInstanceID != nil && $0.featureID == bodyFeatureID }
        .sorted { $0.modelBounds.midX < $1.modelBounds.midX }

    #expect(instanceItems.count == 2)
    #expect(Set(instanceItems.compactMap(\.componentInstanceID)) == Set(source.outputInstanceIDs))
    #expect(abs(instanceItems[0].modelTransform.matrix.values[12] - 0.1) < 1.0e-12)
    #expect(abs(instanceItems[1].modelTransform.matrix.values[12] - 0.2) < 1.0e-12)
    #expect(abs(instanceItems[0].modelBounds.midX - (baseBody.modelBounds.midX + 0.1)) < 1.0e-12)
    #expect(abs(instanceItems[1].modelBounds.midX - (baseBody.modelBounds.midX + 0.2)) < 1.0e-12)

    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))
    let hitPoint = layout.project(CGPoint(
        x: instanceItems[0].modelBounds.midX,
        y: instanceItems[0].modelBounds.midY
    ))
    let hit = try #require(ViewportHitTester().hitTest(
        point: hitPoint,
        in: scene,
        layout: layout,
        selectionHitPolicy: .object
    ))

    #expect(hit.sceneNodeID == instanceItems[0].sceneNodeID)

    _ = try session.execute(.setSceneNodeVisibility(id: source.rootSceneNodeID, isVisible: false))
    let hiddenScene = ViewportSceneBuilder().build(document: session.document)
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

    let scene = ViewportSceneBuilder().build(document: session.document)
    let baseBody = try #require(scene.items.first { item in
        item.componentInstanceID == nil && item.featureID == bodyFeatureID
    })
    let instanceBody = try #require(scene.items.first { item in
        item.componentInstanceID == outputInstanceID && item.featureID == bodyFeatureID
    })

    #expect(abs(instanceBody.modelTransform.matrix.values[12] - 0.13) < 1.0e-12)
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

    let scene = ViewportSceneBuilder().build(document: session.document)
    let baseBody = try #require(scene.items.first { item in
        item.sceneNodeID == bodyNodeID && item.featureID == bodyFeatureID
    })
    let outputBody = try #require(scene.items.first { item in
        guard let sceneNodeID = item.sceneNodeID else {
            return false
        }
        return outputSubtreeIDs.contains(sceneNodeID) && source.outputFeatureIDs.contains(item.featureID)
    })

    #expect(abs(outputBody.modelTransform.matrix.values[12] - 0.1) < 1.0e-12)
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

    let scene = ViewportSceneBuilder().build(document: session.document)
    let outputItems = scene.items.filter {
        $0.componentInstanceID == outputInstanceID && $0.featureID == bodyFeatureID
    }

    #expect(outputItems.count == 1)
    #expect(abs((outputItems.first?.modelTransform.matrix.values[12] ?? 0.0) - 0.05) < 1.0e-12)
}

@MainActor
@Test func viewportSceneBuilderUsesCurrentEvaluatedDocumentWhenAvailable() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluationCache = try #require(session.currentEvaluationCache)

    let documentScene = ViewportSceneBuilder().build(document: session.document)
    let cachedScene = ViewportSceneBuilder().build(
        document: session.document,
        documentGeneration: session.generation,
        evaluationCache: evaluationCache
    )

    #expect(viewportSceneIgnoringEvaluationLocalBodyIDs(cachedScene) == viewportSceneIgnoringEvaluationLocalBodyIDs(documentScene))
}

@MainActor
@Test func viewportSceneBuilderUsesCurrentEvaluationContextWhenAvailable() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(session.currentEvaluation)

    let documentScene = ViewportSceneBuilder().build(document: session.document)
    let contextScene = ViewportSceneBuilder().build(
        document: session.document,
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

    let documentScene = ViewportSceneBuilder().build(document: session.document)
    let staleScene = ViewportSceneBuilder().build(
        document: session.document,
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

    let circleScene = ViewportSceneBuilder().build(document: circleSession.document)
    let mismatchedScene = ViewportSceneBuilder().build(
        document: circleSession.document,
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

    let documentScene = ViewportSceneBuilder().build(document: session.document)
    let staleScene = ViewportSceneBuilder().build(
        document: session.document,
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

    let circleScene = ViewportSceneBuilder().build(document: circleSession.document)
    let mismatchedScene = ViewportSceneBuilder().build(
        document: circleSession.document,
        documentGeneration: rectangleCache.generation,
        evaluationCache: rectangleCache
    )

    #expect(viewportSceneIgnoringEvaluationLocalBodyIDs(mismatchedScene) == viewportSceneIgnoringEvaluationLocalBodyIDs(circleScene))
}

@Test func viewportFaceSurfacePointResolverRestoresPointInsideProjectedFace() throws {
    let componentID = SelectionComponentID.generatedTopology("feature:body:subshape:test:face:front")
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

@MainActor
@Test func viewportSurfaceContinuityOverlayShowsSelectedSurfaceObjectAdjacency() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface Continuity",
        sourceMesh: viewportSurfaceContinuityPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )
    let surfaceNodeID = try #require(bodySceneNodeID(for: featureID, in: document))
    let summary = try SurfaceContinuityService().summarize(document: document)
    let scene = ViewportSceneBuilder().build(document: document)
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
    #expect(item.edgePersistentName.contains("subshape:patch:0:edge:uMax")
        || item.edgePersistentName.contains("subshape:patch:2:edge:uMin"))
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
    let summary = try SurfaceContinuityService().summarize(document: document)
    let adjacency = try #require(summary.adjacencies.first)
    let faceName = try #require(adjacency.firstFacePersistentName)
    let scene = ViewportSceneBuilder().build(document: document)
    var selection = SelectionModel()
    try selection.selectTarget(
        SelectionTarget(
            sceneNodeID: surfaceNodeID,
            component: .face(.generatedTopology(faceName))
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
        .analyze(document: document)
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
        .analyze(document: document)
    let face = try #require(analysis.faces.first)
    let faceName = try #require(face.facePersistentNames.first)
    var selection = SelectionModel()
    try selection.selectTarget(
        SelectionTarget(
            sceneNodeID: surfaceNodeID,
            component: .face(.generatedTopology(faceName))
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
        .analyze(document: document)
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
        .analyze(document: document)
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
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface CV Display",
        sourceMesh: viewportSurfaceAnalysisSingleQuadMesh(topRightZ: 0.0),
        options: PolySplineOptions()
    )
    let initialScene = ViewportSceneBuilder().build(document: document)
    let initialBody = try #require(initialScene.items.first { $0.featureID == featureID })
    guard case .body(let initialComponent) = initialBody.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    #expect(initialComponent.surfaceControlPointDisplays.isEmpty)

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    try document.setSurfaceControlPointDisplay(
        target: controlPoint.selectionReference,
        isVisible: true
    )

    let visibleScene = ViewportSceneBuilder().build(document: document)
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
    let layout = try #require(ViewportLayout(
        scene: visibleScene,
        size: CGSize(width: 900.0, height: 700.0)
    ))
    let hit = try #require(ViewportHitTester().hitTest(
        point: layout.project(display.point, in: visibleBody),
        in: visibleScene,
        layout: layout,
        selectionHitPolicy: .vertex
    ))
    #expect(hit.selectionReference == controlPoint.selectionReference)
    #expect(hit.selectionComponent == nil)

    try document.setSurfaceControlPointDisplay(
        target: controlPoint.selectionReference,
        isVisible: false
    )
    let hiddenScene = ViewportSceneBuilder().build(document: document)
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
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.2, v: 0.2),
                SurfaceParameter(u: 0.8, v: 0.25),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    try document.setSurfaceTrimLoops(target: faceReference, trimLoops: [trimLoop])

    let scene = ViewportSceneBuilder().build(document: document)
    let body = try #require(scene.items.first { $0.featureID == featureID })
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

    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))
    let hit = try #require(ViewportHitTester().hitTest(
        point: layout.project(startDisplay.point, in: body),
        in: scene,
        layout: layout,
        selectionHitPolicy: .vertex
    ))
    #expect(hit.selectionReference == startDisplay.selectionReference)
    #expect(hit.selectionComponent == nil)
}

@Test func viewportSceneBuilderExposesAuthoredSurfaceTrimControlPointDisplays() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createBSplineSurface(
        name: "Viewport Surface Trim Control Point",
        surface: viewportDirectBSplineSurface()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.52, y: 0.42),
                    Point2D(x: 0.8, y: 0.25),
                ]
            ))),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    try document.setSurfaceTrimLoops(target: faceReference, trimLoops: [trimLoop])

    let scene = ViewportSceneBuilder().build(document: document)
    let body = try #require(scene.items.first { $0.featureID == featureID })
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
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.4, y: 0.42),
                    Point2D(x: 0.62, y: 0.38),
                    Point2D(x: 0.8, y: 0.25),
                ]
            ))),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    try document.setSurfaceTrimLoops(target: faceReference, trimLoops: [trimLoop])

    let scene = ViewportSceneBuilder().build(document: document)
    let body = try #require(scene.items.first { $0.featureID == featureID })
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

    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))
    let hit = try #require(ViewportHitTester().hitTest(
        point: layout.project(knotDisplay.point, in: body),
        in: scene,
        layout: layout,
        selectionHitPolicy: .vertex
    ))
    #expect(hit.selectionReference == knotDisplay.selectionReference)

    let index = ViewportIdentityPickIndexBuilder(selectionHitPolicy: .vertex).build(scene: scene)
    #expect(index.records.contains { $0.geometry == .surfaceTrimKnot(knotDisplay.selectionReference) })
    #expect(index.records.contains { $0.geometry == .surfaceTrimSpan(spanDisplay.selectionReference) })
    let plan = ViewportIdentityPickRenderPlanBuilder().build(
        scene: scene,
        layout: layout,
        index: index,
        selectionHitPolicy: .vertex
    )
    #expect(plan.drawItems.contains { $0.hit.selectionReference == knotDisplay.selectionReference })
    #expect(plan.drawItems.contains { $0.hit.selectionReference == spanDisplay.selectionReference })
}

@Test func viewportSceneBuilderExposesDirectSurfaceBasisDisplays() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createBSplineSurface(
        name: "Viewport Surface Basis Parameters",
        surface: viewportEditableDirectBSplineSurface()
    )

    let scene = ViewportSceneBuilder().build(document: document)
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

    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))
    let hit = try #require(ViewportHitTester().hitTest(
        point: layout.project(knotDisplay.point, in: body),
        in: scene,
        layout: layout,
        selectionHitPolicy: .vertex
    ))
    #expect(hit.selectionReference == knotDisplay.selectionReference)

    let index = ViewportIdentityPickIndexBuilder(selectionHitPolicy: .vertex).build(scene: scene)
    #expect(index.records.contains { $0.geometry == .surfaceKnot(knotDisplay.selectionReference) })
    #expect(index.records.contains { $0.geometry == .surfaceSpan(spanDisplay.selectionReference) })
    let plan = ViewportIdentityPickRenderPlanBuilder().build(
        scene: scene,
        layout: layout,
        index: index,
        selectionHitPolicy: .vertex
    )
    #expect(plan.drawItems.contains { $0.hit.selectionReference == knotDisplay.selectionReference })
    #expect(plan.drawItems.contains { $0.hit.selectionReference == spanDisplay.selectionReference })
}

@MainActor
@Test func viewportSceneBuilderExposesVisibleSurfaceFrameDisplays() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Viewport Surface Frame Display",
        sourceMesh: viewportSurfaceAnalysisSingleQuadMesh(topRightZ: 0.0),
        options: PolySplineOptions()
    )
    let initialScene = ViewportSceneBuilder().build(document: document)
    let initialBody = try #require(initialScene.items.first { $0.featureID == featureID })
    guard case .body(let initialComponent) = initialBody.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    #expect(initialComponent.surfaceFrameDisplays.isEmpty)

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 2 && $0.vIndex == 1 })
    let query = SurfaceFrameQuery(selectionReference: controlPoint.selectionReference)
    try document.setSurfaceFrameDisplay(
        query: query,
        isVisible: true
    )

    let expectedFrame = try #require(SurfaceFrameService().resolve(
        document: document,
        queries: [query]
    ).frames.first)
    let visibleScene = ViewportSceneBuilder().build(document: document)
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

    try document.setSurfaceFrameDisplay(
        query: query,
        isVisible: false
    )
    let hiddenScene = ViewportSceneBuilder().build(document: document)
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

    let scene = ViewportSceneBuilder().build(document: session.document)
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
@Test func viewportSceneBuilderCreatesMeshBodyItemForTwistedScaledStraightPathSweep() async throws {
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
    let result = try session.execute(.createSweep(
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

    let scene = ViewportSceneBuilder().build(document: session.document)
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    guard case .body(let component) = bodyItem.kind else {
        Issue.record("Expected a twisted sweep body scene item.")
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

    let scene = ViewportSceneBuilder().build(document: session.document)
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

    let scene = ViewportSceneBuilder().build(document: session.document)
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

    let scene = ViewportSceneBuilder().build(document: session.document)
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

    let scene = ViewportSceneBuilder().build(document: setup.session.document)
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
    #expect(topology.faces.count > 6)
    #expect(topology.edges.count > 12)
    #expect(topology.vertices.count > 8)
    #expect(component.sizeYMeters > 0.05)
    #expect(component.sizeZMeters > 0.05)
}

@MainActor
@Test func viewportHitTesterReturnsGeneratedTopologyForCurvedSweepMesh() async throws {
    let setup = try makeCurvedSweepViewportSession()
    let scene = ViewportSceneBuilder().build(document: setup.session.document)
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
    let topology = try #require(component.topology)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))
    let vertex = try #require(topology.vertices.first)
    let edgeHitTarget = try #require(generatedEdgeHitTarget(
        in: topology,
        scene: scene,
        layout: layout,
        selectionHitPolicy: .edge
    ))
    let faceHitTarget = try #require(generatedFaceHitTarget(
        in: topology,
        scene: scene,
        layout: layout,
        tolerance: 0.0
    ))

    let vertexHit = ViewportHitTester().hitTest(
        point: layout.project(vertex.point),
        in: scene,
        layout: layout
    )
    let edgeHit = ViewportHitTester().hitTest(
        point: edgeHitTarget.point,
        in: scene,
        layout: layout,
        selectionHitPolicy: .edge
    )
    let faceHit = ViewportHitTester(tolerance: 0.0).hitTest(
        point: faceHitTarget.point,
        in: scene,
        layout: layout
    )

    #expect(vertexHit?.selectionComponent == .vertex(vertex.componentID))
    #expect(edgeHit?.selectionComponent == .edge(edgeHitTarget.edge.componentID))
    #expect(faceHit?.selectionComponent == .face(faceHitTarget.face.componentID))
}

@MainActor
@Test func viewportHitTesterReturnsGeneratedPolySplineVertexBeforeFace() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Viewport PolySpline Vertex Hit",
        sourceMesh: viewportSurfaceAnalysisSingleQuadMesh(topRightZ: 0.004),
        options: PolySplineOptions()
    )
    let scene = ViewportSceneBuilder().build(document: document)
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    guard case .body(let component) = bodyItem.kind else {
        Issue.record("Expected a PolySpline body scene item.")
        return
    }
    let topology = try #require(component.topology)
    let vertex = try #require(topology.vertices.first { vertex in
        vertex.componentID.generatedTopologyPersistentName?.contains("generated:polySpline") == true
    })
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let hit = ViewportHitTester().hitTest(
        point: layout.project(vertex.point),
        in: scene,
        layout: layout
    )

    #expect(hit?.selectionComponent == .vertex(vertex.componentID))
}

@MainActor
@Test func viewportSurfaceVertexAxisDragMappingProjectsOntoSelectedAxis() async throws {
    let horizontalAmount = ViewportSurfaceVertexAxisDragMapping.modelAmount(
        axisVector: CGVector(dx: 2.0, dy: 0.0),
        start: CGPoint(x: 10.0, y: 10.0),
        current: CGPoint(x: 20.0, y: 10.0)
    )
    let orthogonalAmount = ViewportSurfaceVertexAxisDragMapping.modelAmount(
        axisVector: CGVector(dx: 2.0, dy: 0.0),
        start: CGPoint(x: 10.0, y: 10.0),
        current: CGPoint(x: 10.0, y: 20.0)
    )
    let diagonalAmount = ViewportSurfaceVertexAxisDragMapping.modelAmount(
        axisVector: CGVector(dx: 3.0, dy: 4.0),
        start: CGPoint(x: 0.0, y: 0.0),
        current: CGPoint(x: 6.0, y: 8.0)
    )
    let yDelta = ViewportSurfaceVertexAxisDragMapping.delta(axis: .y, amount: -1.25)
    let localDelta = ViewportSurfaceVertexAxisDragMapping.delta(
        direction: Vector3D(x: 0.0, y: -1.0, z: 0.0),
        amount: 0.75
    )

    #expect(abs(horizontalAmount - 5.0) < 1.0e-12)
    #expect(abs(orthogonalAmount) < 1.0e-12)
    #expect(abs(diagonalAmount - 2.0) < 1.0e-12)
    #expect(yDelta.x == 0.0)
    #expect(yDelta.y == -1.25)
    #expect(yDelta.z == 0.0)
    #expect(localDelta.x == 0.0)
    #expect(localDelta.y == -0.75)
    #expect(localDelta.z == 0.0)
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

    let scene = ViewportSceneBuilder().build(document: session.document)
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
        if case .arc(_, _, let radiusMeters, let startAngle, let endAngle) = primitive {
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

    let scene = ViewportSceneBuilder().build(document: session.document)
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
        if case .arc(_, let center, let radiusMeters, let startAngle, let endAngle) = primitive {
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

    let scene = ViewportSceneBuilder().build(document: session.document)
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
@Test func viewportHitTesterReportsSplineControlPointIndex() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Viewport Spline Hit",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document)
    let size = CGSize(width: 800.0, height: 600.0)
    let layout = try #require(ViewportLayout(scene: scene, size: size))
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    guard case .sketch(let primitives) = sketchItem.kind,
          case .spline(let entityID, _, let controlPoints, _) = try #require(primitives.first) else {
        Issue.record("Expected a spline sketch primitive.")
        return
    }

    let hit = ViewportHitTester().hitTest(
        point: layout.project(controlPoints[1]),
        in: scene,
        layout: layout
    )

    #expect(hit?.featureID == sketchItem.featureID)
    #expect(hit?.kind == .sketch)
    #expect(hit?.sketchEntityID == entityID)
    #expect(hit?.sketchControlPointIndex == 1)
}

@MainActor
@Test func viewportSelectionRectangleHitTesterHonorsSketchControlPointPolicy() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Viewport Spline Selection Policy",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(
        ViewportLayout(
            scene: scene,
            size: CGSize(width: 800.0, height: 600.0)
        )
    )
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    guard case .sketch(let primitives) = sketchItem.kind,
          case .spline(let entityID, _, _, _) = try #require(primitives.first) else {
        Issue.record("Expected a spline sketch primitive.")
        return
    }
    let selectionRect = CGRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0)

    let hiddenControlPointHits = ViewportSelectionRectangleHitTester().hits(
        in: selectionRect,
        scene: scene,
        layout: layout,
        sketchControlPointHitPolicy: .none
    )
    let visibleControlPointHits = ViewportSelectionRectangleHitTester().hits(
        in: selectionRect,
        scene: scene,
        layout: layout,
        sketchControlPointHitPolicy: .all
    )

    #expect(hiddenControlPointHits.contains {
        $0.sketchEntityID == entityID && $0.sketchControlPointIndex != nil
    } == false)
    #expect(hiddenControlPointHits.contains {
        $0.sketchEntityID == entityID && $0.sketchControlPointIndex == nil
    })
    #expect(visibleControlPointHits.contains {
        $0.sketchEntityID == entityID && $0.sketchControlPointIndex == 1
    })
}

@MainActor
@Test func viewportHitTesterReportsSketchPointHandle() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Viewport Line Hit",
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
    let scene = ViewportSceneBuilder().build(document: session.document)
    let size = CGSize(width: 800.0, height: 600.0)
    let layout = try #require(ViewportLayout(scene: scene, size: size))
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    guard case .sketch(let primitives) = sketchItem.kind,
          case .line(let entityID, _, let end) = try #require(primitives.first) else {
        Issue.record("Expected a line sketch primitive.")
        return
    }

    let hit = ViewportHitTester().hitTest(
        point: layout.project(end),
        in: scene,
        layout: layout
    )

    #expect(hit?.featureID == sketchItem.featureID)
    #expect(hit?.kind == .sketch)
    #expect(hit?.sketchEntityID == entityID)
    #expect(hit?.sketchPointHandle == .lineEnd)
    #expect(hit?.sketchControlPointIndex == nil)
}

@Test func viewportPickingReadinessReportsProjectedGeneratedTopologyTargets() throws {
    let scene = viewportGeneratedTopologyScene()

    let summary = ViewportPickingReadinessService().summarize(scene: scene)

    #expect(summary.activeBackend == .projectedCPU)
    #expect(summary.requiredBackend == .identityBuffer)
    #expect(summary.bodyTargetCount == 1)
    #expect(summary.generatedFaceTargetCount == 1)
    #expect(summary.generatedEdgeTargetCount == 1)
    #expect(summary.generatedVertexTargetCount == 1)
    #expect(summary.identityTargetCount == 4)
    #expect(summary.supportsObjectTargets)
    #expect(summary.supportsGeneratedFaceTargets)
    #expect(summary.supportsGeneratedEdgeTargets)
    #expect(summary.supportsGeneratedVertexTargets)
    #expect(summary.supportsGeneratedTopologyTargets)
    #expect(summary.supportsIdentityTargetIndex)
    #expect(summary.isExactIdentityBacked == false)
    #expect(summary.activeBackendTitle == "CPU")
    #expect(summary.nextBackendTitle == "Identity")
}

@Test func viewportPickingReadinessReportsIdentityBackendAsReady() throws {
    let scene = viewportGeneratedTopologyScene()

    let summary = ViewportPickingReadinessService()
        .summarize(scene: scene, activeBackend: .identityBuffer)

    #expect(summary.activeBackend == .identityBuffer)
    #expect(summary.isExactIdentityBacked)
    #expect(summary.activeBackendTitle == "Identity")
    #expect(summary.nextBackendTitle == "Ready")
}

@Test func viewportPickingReadinessReportsIdentityRenderBudgetEstimate() throws {
    let scene = viewportGeneratedTopologyScene()
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 240.0, height: 180.0)
    ))

    let summary = ViewportPickingReadinessService()
        .summarize(scene: scene, layout: layout)

    #expect(summary.hasIdentityBudgetEstimate)
    #expect(summary.isIdentityRenderWithinBudget)
    #expect(summary.identityRenderCost?.pixelCount == 43_200)
    #expect((summary.identityRenderCost?.drawItemCount ?? 0) > 0)
    #expect((summary.identityRenderCost?.encodedPointCount ?? 0) > 0)
    #expect(summary.identityRenderCost?.identityRecordCount == summary.identityTargetCount)
    #expect(summary.identityBudgetRejection == nil)
    #expect(summary.identityBudgetStatusTitle == "Within budget")
    #expect(summary.identityBudgetCalibration == .fixedStandard)
    #expect(summary.identityBudgetCalibrationTitle == "Fixed standard")
    #expect(summary.nextBackendTitle == "Identity")
}

@Test func viewportPickingReadinessReportsDenseTopologyBudgetEstimate() throws {
    let scene = denseGeneratedTopologyScene(columns: 100, rows: 100)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 1_280.0, height: 720.0)
    ))

    let summary = ViewportPickingReadinessService()
        .summarize(scene: scene, layout: layout)
    let cost = try #require(summary.identityRenderCost)

    #expect(summary.hasIdentityBudgetEstimate)
    #expect(summary.isIdentityRenderWithinBudget)
    #expect(summary.identityTargetCount == 10_001)
    #expect(cost.pixelCount == 921_600)
    #expect(cost.drawItemCount == 20_000)
    #expect(cost.encodedPointCount == 80_000)
    #expect(
        cost.estimatedIdentityIndexByteCount ==
            10_001 * ViewportIdentityHitResolver.RenderCost.identityIndexBytesPerRecord
    )
    #expect(
        cost.estimatedResidentByteCount ==
            8_652_816 + cost.estimatedIdentityIndexByteCount
    )
    #expect(summary.identityBudgetRejection == nil)
    #expect(summary.identityBudgetStatusTitle == "Within budget")
    #expect(summary.nextBackendTitle == "Identity")
}

@Test func viewportPickingReadinessReportsDeviceCalibratedBudgetProfile() throws {
    let scene = denseGeneratedTopologyScene(columns: 100, rows: 100)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 1_280.0, height: 720.0)
    ))
    let budget = ViewportIdentityHitResolver.RenderBudget.deviceCalibrated(
        recommendedMaxWorkingSetSize: 16 * 1024 * 1024 * 1024,
        isLowPower: false,
        hasUnifiedMemory: false
    )

    let summary = ViewportPickingReadinessService()
        .summarize(scene: scene, layout: layout, renderBudget: budget)

    #expect(summary.hasIdentityBudgetEstimate)
    #expect(summary.isIdentityRenderWithinBudget)
    #expect(summary.identityBudgetCalibration == .discreteOrHighThroughput)
    #expect(summary.identityBudgetCalibrationTitle == "Discrete or high-throughput")
    #expect(summary.identityBudgetRejection == nil)
    #expect(summary.nextBackendTitle == "Identity")
}

@Test func viewportPickingReadinessReportsIdentityBudgetRejection() throws {
    let scene = viewportGeneratedTopologyScene()
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 240.0, height: 180.0)
    ))

    let summary = ViewportPickingReadinessService()
        .summarize(
            scene: scene,
            layout: layout,
            renderBudget: ViewportIdentityHitResolver.RenderBudget(
                maximumPixelCount: 1,
                maximumDrawItemCount: 200_000,
                maximumEncodedPointCount: 1_000_000
            )
        )

    #expect(summary.hasIdentityBudgetEstimate)
    #expect(summary.isIdentityRenderWithinBudget == false)
    #expect(summary.identityBudgetRejection?.limit == .pixelCount)
    #expect(summary.identityBudgetRejection?.calibration == .fixedStandard)
    #expect(summary.identityBudgetRejection?.actual == 43_200)
    #expect(summary.identityBudgetRejection?.maximum == 1)
    #expect(summary.identityBudgetStatusTitle == "Pixel budget exceeded")
    #expect(summary.nextBackendTitle == "CPU")
}

@Test func viewportPickingReadinessReportsIdentityMemoryBudgetRejection() throws {
    let scene = viewportGeneratedTopologyScene()
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 240.0, height: 180.0)
    ))

    let summary = ViewportPickingReadinessService()
        .summarize(
            scene: scene,
            layout: layout,
            renderBudget: ViewportIdentityHitResolver.RenderBudget(
                maximumPixelCount: 8_294_400,
                maximumDrawItemCount: 200_000,
                maximumEncodedPointCount: 1_000_000,
                maximumEstimatedResidentByteCount: 1
            )
        )

    #expect(summary.hasIdentityBudgetEstimate)
    #expect(summary.isIdentityRenderWithinBudget == false)
    #expect(summary.identityBudgetRejection?.limit == .estimatedResidentByteCount)
    #expect((summary.identityBudgetRejection?.actual ?? 0) > 1)
    #expect(summary.identityBudgetRejection?.maximum == 1)
    #expect(summary.identityBudgetStatusTitle == "Memory budget exceeded")
    #expect(summary.nextBackendTitle == "CPU")
}

@Test func viewportIdentityPickIndexBuildsDecodableGeneratedTopologyRecords() throws {
    let scene = viewportGeneratedTopologyScene()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:vertex:frontBottomLeft"
    )

    let index = ViewportIdentityPickIndexBuilder().build(scene: scene)
    let faceRecord = try #require(index.records.first {
        $0.geometry == .generatedFace(faceComponentID)
    })
    let edgeRecord = try #require(index.records.first {
        $0.geometry == .generatedEdge(edgeComponentID)
    })
    let vertexRecord = try #require(index.records.first {
        $0.geometry == .generatedVertex(vertexComponentID)
    })

    #expect(ViewportPickIdentity(rawValue: ViewportPickIdentity.backgroundRawValue) == nil)
    #expect(index.count == 4)
    #expect(index.records.map(\.identity.rawValue) == [1, 2, 3, 4])
    #expect(index.hit(for: faceRecord.identity)?.pickingBackend == .identityBuffer)
    #expect(index.hit(for: faceRecord.identity)?.selectionComponent == .face(faceComponentID))
    #expect(index.hit(for: edgeRecord.identity)?.selectionComponent == .edge(edgeComponentID))
    #expect(index.hit(for: vertexRecord.identity)?.selectionComponent == .vertex(vertexComponentID))
}

@Test func viewportIdentityPickRenderPlanBuildsGeneratedTopologyDrawItems() throws {
    let scene = viewportGeneratedTopologyScene()
    let layout = try #require(
        ViewportLayout(
            scene: scene,
            size: CGSize(width: 800.0, height: 600.0)
        )
    )
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:vertex:frontBottomLeft"
    )

    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let faceItem = try #require(plan.drawItems.first {
        $0.geometry == .generatedFace(faceComponentID)
    })
    let edgeItem = try #require(plan.drawItems.first {
        $0.geometry == .generatedEdge(edgeComponentID)
    })
    let vertexItem = try #require(plan.drawItems.first {
        $0.geometry == .generatedVertex(vertexComponentID)
    })

    #expect(plan.index.count == 4)
    #expect(plan.drawItems(for: faceItem.identity).isEmpty == false)
    #expect(faceItem.hit.pickingBackend == .identityBuffer)
    #expect(faceItem.hit.selectionComponent == .face(faceComponentID))
    #expect(faceItem.depth != nil)
    if case .polygon(let points) = faceItem.primitive {
        #expect(points.count == 4)
    } else {
        Issue.record("Expected generated face to render as a polygon.")
    }
    if case .segment(_, _, let radius) = edgeItem.primitive {
        #expect(radius == 4.0)
    } else {
        Issue.record("Expected generated edge to render as a segment.")
    }
    if case .point(_, let radius) = vertexItem.primitive {
        #expect(radius == 6.0)
    } else {
        Issue.record("Expected generated vertex to render as a point.")
    }
}

@MainActor
@Test func viewportIdentityPickIndexIncludesProjectedBodyFallbackWhenTopologyIsMissing() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)

    let index = ViewportIdentityPickIndexBuilder().build(scene: scene)

    #expect(index.records.contains { $0.geometry == .projectedBodyFace(.front) })
    #expect(index.records.contains { $0.geometry == .projectedBodyEdge(.rightTop) })
    #expect(index.records.contains { $0.geometry == .projectedBodyVertex(.backTopRight) })
    #expect(index.records.allSatisfy { $0.identity.rawValue > ViewportPickIdentity.backgroundRawValue })
    #expect(index.records.allSatisfy { $0.hit.pickingBackend == .identityBuffer })
}

@MainActor
@Test func viewportIdentityPickRenderPlanBuildsProjectedBodyFallbackDrawItems() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(
        ViewportLayout(
            scene: scene,
            size: CGSize(width: 800.0, height: 600.0)
        )
    )

    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let faceItem = try #require(plan.drawItems.first {
        $0.geometry == .projectedBodyFace(.front)
    })
    let edgeItem = try #require(plan.drawItems.first {
        $0.geometry == .projectedBodyEdge(.rightTop)
    })
    let vertexItem = try #require(plan.drawItems.first {
        $0.geometry == .projectedBodyVertex(.backTopRight)
    })

    #expect(faceItem.hit.pickingBackend == .identityBuffer)
    #expect(edgeItem.hit.pickingBackend == .identityBuffer)
    #expect(vertexItem.hit.pickingBackend == .identityBuffer)
    if case .polygon(let points) = faceItem.primitive {
        #expect(points.count == 4)
    } else {
        Issue.record("Expected projected body face to render as a polygon.")
    }
    if case .segment = edgeItem.primitive {
        #expect(edgeItem.hit.bodyEdge == .rightTop)
    } else {
        Issue.record("Expected projected body edge to render as a segment.")
    }
    if case .point = vertexItem.primitive {
        #expect(vertexItem.hit.bodyVertex == .backTopRight)
    } else {
        Issue.record("Expected projected body vertex to render as a point.")
    }
}

@Test func viewportIdentityPickRenderPlanCarriesMeshStorageIdentityForMeshFallbackDrawItems() throws {
    let mesh = ViewportBodyMesh(
        positions: [
            Point3D(x: -0.010, y: 0.0, z: -0.010),
            Point3D(x: 0.010, y: 0.0, z: -0.010),
            Point3D(x: 0.0, y: 0.0, z: 0.010),
        ],
        indices: [0, 1, 2]
    )
    let component = ViewportBodyComponent(
        sizeXMeters: 0.020,
        sizeYMeters: 0.001,
        sizeZMeters: 0.020,
        yMinMeters: 0.0,
        yMaxMeters: 0.001,
        mesh: mesh
    )
    let featureID = FeatureID()
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: featureID.description,
            featureID: featureID,
            modelBounds: CGRect(x: -0.010, y: -0.010, width: 0.020, height: 0.020),
            kind: .body(component: component)
        )
    ])
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 800.0, height: 600.0)
    ))

    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let meshItems = plan.drawItems.filter { $0.meshStorageIdentity != nil }
    let bodyItem = try #require(meshItems.first { $0.geometry == .body })

    #expect(meshItems.count == 1)
    #expect(bodyItem.meshStorageIdentity == mesh.storageIdentity)
    #expect(bodyItem.meshPrimitiveIndex == 0)
    #expect(bodyItem.hit.pickingBackend == .identityBuffer)
    if case .polygon(let points) = bodyItem.primitive {
        #expect(points.count == 3)
    } else {
        Issue.record("Expected mesh fallback body draw item to render as a triangle polygon.")
    }
}

@MainActor
@Test func viewportIdentityPickIndexCanOmitSketchControlPointRecords() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Viewport Identity Spline Policy",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document)

    let hiddenIndex = ViewportIdentityPickIndexBuilder(includesSketchControlPoints: false)
        .build(scene: scene)
    let visibleIndex = ViewportIdentityPickIndexBuilder(includesSketchControlPoints: true)
        .build(scene: scene)

    #expect(hiddenIndex.records.contains { record in
        if case .sketchControlPoint = record.geometry {
            return true
        }
        return false
    } == false)
    #expect(visibleIndex.records.contains { record in
        if case .sketchControlPoint(_, 1) = record.geometry {
            return true
        }
        return false
    })
}

@MainActor
@Test func viewportIdentityPickRenderPlanUsesProvidedSketchControlPointIndexPolicy() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Viewport Identity Spline Render Policy",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(
        ViewportLayout(
            scene: scene,
            size: CGSize(width: 800.0, height: 600.0)
        )
    )
    let hiddenIndex = ViewportIdentityPickIndexBuilder(includesSketchControlPoints: false)
        .build(scene: scene)
    let hiddenPlan = ViewportIdentityPickRenderPlanBuilder()
        .build(scene: scene, layout: layout, index: hiddenIndex)
    let visiblePlan = ViewportIdentityPickRenderPlanBuilder()
        .build(scene: scene, layout: layout)

    #expect(hiddenPlan.drawItems.contains { drawItem in
        if case .sketchControlPoint = drawItem.geometry {
            return true
        }
        return false
    } == false)
    #expect(visiblePlan.drawItems.contains { drawItem in
        if case .sketchControlPoint(_, 1) = drawItem.geometry,
           case .point = drawItem.primitive {
            return true
        }
        return false
    })
}

@Test func viewportHitCarriesPickingBackendForGeneratedTopologyHit() throws {
    let scene = viewportGeneratedTopologyScene()
    let layout = try #require(
        ViewportLayout(
            scene: scene,
            size: CGSize(width: 800.0, height: 600.0)
        )
    )
    let vertexPoint = Point3D(x: -0.010, y: 0.0, z: -0.010)
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:vertex:frontBottomLeft"
    )

    let hit = ViewportHitTester().hitTest(
        point: layout.project(vertexPoint),
        in: scene,
        layout: layout
    )

    #expect(hit?.kind == .body)
    #expect(hit?.pickingBackend == .projectedCPU)
    #expect(hit?.selectionComponent == .vertex(vertexComponentID))
}

@Test func viewportHitTesterSelectsNearestGeneratedFaceWhenFacesOverlapInProjection() throws {
    let fixture = try overlappingGeneratedFaceScene()
    let layout = try #require(
        ViewportLayout(
            scene: fixture.scene,
            size: CGSize(width: 800.0, height: 600.0)
        )
    )

    let hit = ViewportHitTester(tolerance: 0.0).hitTest(
        point: layout.project(fixture.nearCenter),
        in: fixture.scene,
        layout: layout
    )

    #expect(hit?.featureID == fixture.nearFeatureID)
    #expect(hit?.selectionComponent == .face(fixture.nearFaceComponentID))
}

@Test func viewportBodyTopologyHitTesterDepthBreaksTiesForOverlappingTopologyPrimitives() throws {
    let fixture = try overlappingGeneratedPrimitiveComponent()
    let layout = ViewportLayout(
        modelBounds: fixture.modelBounds,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let hitPoint = layout.project(fixture.nearCenter)

    let vertexHit = ViewportBodyTopologyHitTester().hitTest(
        item: fixture.item,
        component: fixture.vertexComponent,
        point: hitPoint,
        layout: layout
    )
    let edgeHit = ViewportBodyTopologyHitTester().hitTest(
        item: fixture.item,
        component: fixture.edgeComponent,
        point: hitPoint,
        layout: layout
    )
    let faceHit = ViewportBodyTopologyHitTester(tolerance: 0.0).hitTest(
        item: fixture.item,
        component: fixture.faceComponent,
        point: hitPoint,
        layout: layout
    )

    #expect(vertexHit?.component == .vertex(fixture.nearVertexComponentID))
    #expect(edgeHit?.component == .edge(fixture.nearEdgeComponentID))
    #expect(faceHit?.component == .face(fixture.nearFaceComponentID))
}

@Test func viewportSelectionRectangleHitTesterReturnsGeneratedTopologySubobjectHits() throws {
    let scene = viewportGeneratedTopologyScene()
    let layout = try #require(
        ViewportLayout(
            scene: scene,
            size: CGSize(width: 800.0, height: 600.0)
        )
    )
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:vertex:frontBottomLeft"
    )

    let hits = ViewportSelectionRectangleHitTester().hits(
        in: CGRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0),
        scene: scene,
        layout: layout
    )

    #expect(hits.contains { $0.selectionComponent == .face(faceComponentID) })
    #expect(hits.contains { $0.selectionComponent == .edge(edgeComponentID) })
    #expect(hits.contains { $0.selectionComponent == .vertex(vertexComponentID) })
    #expect(hits.contains { $0.kind == .body && $0.selectionComponent == nil })
}

@MainActor
@Test func viewportSelectionRectangleHitTesterReturnsProjectedBodySubobjectHitsWhenTopologyIsMissing() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(
        ViewportLayout(
            scene: scene,
            size: CGSize(width: 800.0, height: 600.0)
        )
    )

    let hits = ViewportSelectionRectangleHitTester().hits(
        in: CGRect(x: 0.0, y: 0.0, width: 800.0, height: 600.0),
        scene: scene,
        layout: layout
    )

    #expect(hits.contains { $0.bodyFace != nil })
    #expect(hits.contains { $0.bodyEdge != nil })
    #expect(hits.contains { $0.bodyVertex != nil })
    #expect(hits.contains { $0.kind == .body && $0.selectionComponent == nil })
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
    let scene = ViewportSceneBuilder().build(document: session.document)
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

@MainActor
@Test func viewportHitTesterReportsSketchRegionInteriorWithoutStealingEdges() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Viewport Hit Region",
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
    let scene = ViewportSceneBuilder().build(document: session.document)
    let size = CGSize(width: 800.0, height: 600.0)
    let layout = try #require(ViewportLayout(scene: scene, size: size))
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })
    let region = try #require(sketchItem.sketchRegions.first)
    guard case .sketch(let primitives) = sketchItem.kind,
          case .line(let edgeEntityID, let edgeStart, let edgeEnd) = try #require(primitives.first) else {
        Issue.record("Expected a line sketch primitive.")
        return
    }

    let interiorHit = ViewportHitTester().hitTest(
        point: layout.project(center(of: region.points)),
        in: scene,
        layout: layout
    )
    let edgeMidpoint = CGPoint(
        x: (edgeStart.x + edgeEnd.x) / 2.0,
        y: (edgeStart.y + edgeEnd.y) / 2.0
    )
    let edgeHit = ViewportHitTester().hitTest(
        point: layout.project(edgeMidpoint),
        in: scene,
        layout: layout
    )

    #expect(interiorHit?.featureID == sketchItem.featureID)
    #expect(interiorHit?.kind == .sketch)
    #expect(interiorHit?.selectionComponent == .region(region.componentID))
    #expect(interiorHit?.sketchEntityID == nil)
    #expect(edgeHit?.featureID == sketchItem.featureID)
    #expect(edgeHit?.kind == .sketch)
    #expect(edgeHit?.sketchEntityID == edgeEntityID)
    #expect(edgeHit?.selectionComponent == nil)
}

@MainActor
@Test func viewportHitTesterSelectsBodyInteriorAndSketchEdges() async throws {
    let session = EditorSession()
    let sketchResult = try session.execute(
        .createRectangleSketch(
            name: "Hit Test Profile",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter)
        )
    )
    let sketchFeatureID = try #require(sketchResult.primaryFeatureID)
    _ = try session.execute(
        .extrudeProfile(
            name: "Hit Test Body",
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .length(10.0, .millimeter),
            direction: .normal
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document)
    let size = CGSize(width: 800.0, height: 600.0)
    let layout = try #require(ViewportLayout(scene: scene, size: size))
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    let sketchItem = try #require(scene.items.first { item in
        if case .sketch = item.kind {
            return true
        }
        return false
    })

    let bodyPoint = layout.project(
        CGPoint(
            x: bodyItem.modelBounds.midX,
            y: bodyItem.modelBounds.midY
        )
    )
    let bodyHit = ViewportHitTester().hitTest(
        point: bodyPoint,
        in: scene,
        size: size
    )

    let sketchEdgePoint = layout.project(
        CGPoint(
            x: sketchItem.modelBounds.minX,
            y: sketchItem.modelBounds.midY
        )
    )
    let sketchHit = ViewportHitTester().hitTest(
        point: sketchEdgePoint,
        in: scene,
        size: size
    )

    #expect(bodyHit?.featureID == bodyItem.featureID)
    #expect(bodyHit?.kind == .body)
    #expect(bodyHit?.bodyFace != nil)
    #expect(sketchHit?.featureID == sketchItem.featureID)
    #expect(sketchHit?.kind == .sketch)
    #expect(sketchHit?.sketchEntityID != nil)
}

@MainActor
@Test func viewportHitTesterSelectsBodyVertexBeforeEdgesAndFaces() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)
    let size = CGSize(width: 800.0, height: 600.0)
    let layout = try #require(ViewportLayout(scene: scene, size: size))
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    let projection = try #require(layout.bodyProjection(for: bodyItem))

    let hit = ViewportHitTester().hitTest(
        point: projection.point(for: .backTopRight),
        in: scene,
        layout: layout
    )

    #expect(hit?.featureID == bodyItem.featureID)
    #expect(hit?.kind == .body)
    #expect(hit?.bodyVertex == .backTopRight)
    #expect(hit?.bodyEdge == nil)
    #expect(hit?.bodyFace == nil)
}

@MainActor
@Test func viewportHitTesterReturnsNilForBackground() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)

    let hit = ViewportHitTester().hitTest(
        point: CGPoint(x: 8.0, y: 8.0),
        in: scene,
        size: CGSize(width: 800.0, height: 600.0)
    )

    #expect(hit == nil)
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
        (size.width - 180.0) / expectedBounds.width,
        (size.height - 140.0) / expectedBounds.height
    )

    #expect(abs(layout.scale - expectedScale) < expectedScale * 1.0e-12)
    #expect(abs(unprojectedPoint.x - modelPoint.x) < 1.0e-15)
    #expect(abs(unprojectedPoint.y - modelPoint.y) < 1.0e-15)
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

    let start = geometry.projectedTip(layout: layout)
    let outwardEnd = geometry.projectedTip(layout: layout, distanceMeters: 0.25)
    let inwardEnd = geometry.projectedTip(layout: layout, distanceMeters: -0.125)

    #expect(geometry.modelDirection.x > 0.0)
    #expect(abs(geometry.offsetDistance(start: start, current: outwardEnd, layout: layout) - 0.25) < 1.0e-12)
    #expect(abs(geometry.offsetDistance(start: start, current: inwardEnd, layout: layout) + 0.125) < 1.0e-12)
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

    let start = geometry.projectedTip(layout: layout)
    let widerEnd = geometry.projectedTip(layout: layout, widthMeters: 1.4)
    let narrowerEnd = geometry.projectedTip(layout: layout, widthMeters: 0.8)

    #expect(abs(geometry.modelDirection.x) < 1.0e-12)
    #expect(abs(geometry.slotWidth(start: start, current: widerEnd, layout: layout) - 1.4) < 1.0e-12)
    #expect(abs(geometry.slotWidth(start: start, current: narrowerEnd, layout: layout) - 0.8) < 1.0e-12)
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

    let start = geometry.projectedTip(layout: layout)
    let fartherEnd = geometry.projectedTip(layout: layout, distanceMeters: 1.25)
    let nearerEnd = geometry.projectedTip(layout: layout, distanceMeters: 0.75)

    #expect(abs(geometry.modelDirection.x - 1.0) < 1.0e-12)
    #expect(abs(geometry.offsetDistance(start: start, current: fartherEnd, layout: layout) - 1.25) < 1.0e-12)
    #expect(abs(geometry.offsetDistance(start: start, current: nearerEnd, layout: layout) - 0.75) < 1.0e-12)
}

@Test func viewportModelCoordinateMapperProvidesEmptyDocumentDragPlane() {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.micrometer)
    let mapper = ViewportModelCoordinateMapper(
        document: document,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let centerPoint = mapper.modelPoint(for: CGPoint(x: 400.0, y: 300.0))
    let drag = mapper.modelDrag(
        from: CGPoint(x: 360.0, y: 320.0),
        to: CGPoint(x: 440.0, y: 280.0)
    )
    let expectedSpan = max(
        document.ruler.visibleSpanMeters,
        document.ruler.majorTickMeters * 20.0,
        document.ruler.minorTickMeters * 40.0
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
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
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
    let scene = ViewportSceneBuilder().build(document: document)
    let sceneBounds = try #require(scene.modelBounds)
    let mapper = ViewportModelCoordinateMapper(
        document: document,
        scene: scene,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let ruler = document.ruler.normalizedForWorkspaceScale()
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
    #expect(Double(mapper.layout.modelBounds.width) < document.ruler.visibleSpanMeters)
    #expect(Double(mapper.layout.modelBounds.height) < document.ruler.visibleSpanMeters)
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
        (size.width - 180.0) / expectedBounds.width,
        (size.height - 140.0) / expectedBounds.height
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
    #expect(projectedWidth <= size.width - 180.0 + 1.0e-9)
    #expect(projectedHeight <= size.height - 140.0 + 1.0e-9)
}

@MainActor
@Test func viewportSceneProjectsZXCanvasSketchBackToCanvasCoordinates() async throws {
    let session = EditorSession()
    session.selectTool(.sketch)

    _ = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.03, y: 0.04),
        sketchPlane: .zx
    )

    let scene = ViewportSceneBuilder().build(document: session.document)
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
        size: size
    )
    let modelPoint = initialMapper.modelPoint(for: clickPoint)

    session.selectTool(.sketch)
    _ = session.activateSelectedToolFromCanvas(
        targetSceneNodeID: nil,
        modelPoint: modelPoint,
        sketchPlane: .zx
    )

    let finalMapper = ViewportModelCoordinateMapper(
        document: session.document,
        size: size
    )
    let finalPoint = finalMapper.layout.project(
        CGPoint(x: modelPoint.x, y: modelPoint.y)
    )

    #expect(abs(finalPoint.x - clickPoint.x) < 1.0e-9)
    #expect(abs(finalPoint.y - clickPoint.y) < 1.0e-9)
}

@Test func viewportCanvasDragPlaceholderUsesCoordinateAlignedFootprintOnEmptyDocument() throws {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.millimeter)
    let mapper = ViewportModelCoordinateMapper(
        document: document,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let drag = mapper.modelDrag(
        from: CGPoint(x: 320.0, y: 360.0),
        to: CGPoint(x: 500.0, y: 280.0)
    )
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
    let zEdge = CGVector(
        dx: placeholder.footprint.topLeft.x - placeholder.footprint.bottomLeft.x,
        dy: placeholder.footprint.topLeft.y - placeholder.footprint.bottomLeft.y
    )

    #expect(placeholder.modelBounds.width > 0.0)
    #expect(placeholder.modelBounds.height > 0.0)
    #expect(isParallel(xEdge, mapper.layout.basis.xDirection))
    #expect(isParallel(zEdge, mapper.layout.basis.zDirection))
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
        sketchPlane: .xy
    )
    let options = SnapResolutionOptions(
        usesGrid: false,
        usesObjects: false
    )

    let resolved = ViewportCanvasDragSnapResolver().resolvedDrag(
        drag,
        document: .empty(),
        snapOptions: options,
        axisConstraint: .x
    )

    #expect(pointIsApproximatelyEqual(resolved.start, drag.start))
    #expect(pointIsApproximatelyEqual(resolved.end, Point2D(x: drag.end.x, y: drag.start.y)))
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
    var document = DesignDocument.empty()
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    let size = CGSize(width: 800.0, height: 600.0)
    let identityLayout = ViewportModelCoordinateMapper(
        document: document,
        size: size
    ).layout
    let maximumZoom = ViewportCameraZoomPolicy.maximumZoom(
        for: document,
        identityScale: identityLayout.scale
    )
    let zoomedLayout = ViewportModelCoordinateMapper(
        document: document,
        size: size,
        camera: ViewportCamera(zoom: maximumZoom * 2.0)
    ).layout
    let minorTickPixels = CGFloat(document.ruler.minorTickMeters) * zoomedLayout.scale
    let meterPixels = zoomedLayout.scale

    #expect(maximumZoom > ViewportCamera.maximumZoom)
    #expect(identityLayout.maximumZoom == maximumZoom)
    #expect(minorTickPixels >= ViewportCameraZoomPolicy.targetMinorTickPixels - 0.001)
    #expect(meterPixels >= ViewportCameraZoomPolicy.targetMinorTickPixels - 0.001)
}

@MainActor
@Test func viewportTopChromeUsesCompactCanvasOverlayMetrics() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(viewportSize: viewportSize)
    let rect = layout.viewportBadgeRect

    #expect(
        ViewportCanvasChromeLayout.viewportBadgeHeight
            == ViewportCanvasChromeMetrics.topControlHeight
    )
    #expect(
        ViewportCanvasChromeLayout.maximumViewportBadgeWidth
            == ViewportCanvasChromeMetrics.topControlMaximumWidth
    )
    #expect(
        ViewportCanvasChromeLayout.defaultViewportBadgeWidth
            < ViewportCanvasChromeMetrics.topControlMaximumWidth
    )
    #expect(ViewportCanvasChromeLayout.defaultViewportBadgeWidth == ViewportCanvasChromeLayout.minimumViewportBadgeWidth)
    #expect(ViewportCanvasChromeLayout.defaultViewportBadgeWidth == 112.0)
    #expect(ViewportCanvasChromeMetrics.topControlMaximumWidth == 168.0)
    #expect(ViewportCanvasChromeLayout.viewportBadgePadding == ViewportCanvasChromeMetrics.edgePadding)
    #expect(ViewportCanvasChromeMetrics.topControlContentHeight < ViewportCanvasChromeMetrics.topControlHeight)
    #expect(
        ViewportCanvasChromeMetrics.topControlDividerHeight
            <= ViewportCanvasChromeMetrics.topControlContentHeight
    )
    #expect(ViewportCanvasChromeMetrics.topControlHorizontalPadding == ViewportCanvasChromeMetrics.edgePadding)
    #expect(ViewportCanvasChromeMetrics.topControlItemSpacing <= ViewportCanvasChromeMetrics.edgePadding)
    #expect(ViewportCanvasChromeMetrics.borderWidth == 0.0)
    #expect(ViewportCanvasChromeMetrics.borderOpacity == 0.0)
    #expect(rect.minX == ViewportCanvasChromeLayout.viewportBadgePadding)
    #expect(rect.minY == ViewportCanvasChromeLayout.viewportBadgePadding)
    #expect(rect.width == ViewportCanvasChromeLayout.defaultViewportBadgeWidth)
    #expect(rect.height == ViewportCanvasChromeLayout.viewportBadgeHeight)
    #expect(layout.containsCanvasChrome(CGPoint(x: 12.0, y: 12.0)))
}

@MainActor
@Test func viewportTopChromeBadgeWidthCanTrackCompactContent() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let compactWidth = CGFloat(156.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        viewportBadgeWidth: compactWidth
    )
    let rect = layout.viewportBadgeRect

    #expect(rect.width == compactWidth)
    #expect(rect.width < ViewportCanvasChromeMetrics.topControlMaximumWidth)
}

@MainActor
@Test func viewportTopChromeBadgeAvoidsExternalOverlayExclusions() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let topOverlayRect = CGRect(x: 0.0, y: 0.0, width: 420.0, height: 46.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        additionalExclusionRects: [topOverlayRect]
    )
    let rect = layout.viewportBadgeRect

    #expect(rect.minX == ViewportCanvasChromeLayout.viewportBadgePadding)
    #expect(rect.minY > topOverlayRect.maxY)
    #expect(!rect.intersects(topOverlayRect))
    #expect(layout.containsCanvasChrome(CGPoint(x: 12.0, y: topOverlayRect.maxY + 16.0)))
    #expect(!rect.contains(CGPoint(x: 12.0, y: 12.0)))
}

@MainActor
@Test func viewportTopChromeBadgeStaysVisibleBesideTrailingCommandChrome() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let trailingOverlayRect = CGRect(x: 620.0, y: 0.0, width: 174.0, height: 42.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        additionalExclusionRects: [trailingOverlayRect]
    )
    let rect = layout.viewportBadgeRect

    #expect(rect.minX == ViewportCanvasChromeLayout.viewportBadgePadding)
    #expect(rect.minY == ViewportCanvasChromeLayout.viewportBadgePadding)
    #expect(!rect.intersects(trailingOverlayRect))
    #expect(layout.containsCanvasChrome(CGPoint(x: trailingOverlayRect.midX, y: trailingOverlayRect.midY)))
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
    #expect(layout.inputExclusionRects.count == 2)
    #expect(layout.containsCanvasChrome(CGPoint(x: 20.0, y: 20.0)))
    #expect(!layout.containsCanvasChrome(CGPoint(x: viewportSize.width / 2.0, y: viewportSize.height / 2.0)))
}

@MainActor
@Test func viewportCanvasChromeLayoutDetectsScaleLabelOverlap() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(viewportSize: viewportSize)
    let topLabelRect = CGRect(x: 12.0, y: 12.0, width: 80.0, height: 16.0)
    let centerLabelRect = CGRect(x: 360.0, y: 292.0, width: 80.0, height: 16.0)

    #expect(layout.intersectsCanvasChrome(topLabelRect))
    #expect(layout.intersectsCanvasChrome(layout.axisControlRect))
    #expect(!layout.intersectsCanvasChrome(centerLabelRect))
}

@MainActor
@Test func viewportCanvasChromeLayoutMergesExternalOverlayExclusions() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let overlayRect = CGRect(x: 612.0, y: 44.0, width: 38.0, height: 210.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        additionalExclusionRects: [overlayRect]
    )

    #expect(layout.inputExclusionRects.count == 3)
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
}

@MainActor
@Test func viewportCanvasChromeLayoutPlacesSnapLabelsAwayFromOverlayChrome() {
    let viewportSize = CGSize(width: 800.0, height: 600.0)
    let rightOverlayRect = CGRect(x: 700.0, y: 0.0, width: 100.0, height: 600.0)
    let layout = ViewportCanvasChromeLayout(
        viewportSize: viewportSize,
        additionalExclusionRects: [rightOverlayRect]
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
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(60.0, .millimeter),
        // 90-180 degrees keeps the path start directly above the profile-plane
        // origin under the anchored placement semantics.
        startAngle: .angle(90.0, .degree),
        endAngle: .angle(180.0, .degree)
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

private func generatedEdgeHitTarget(
    in topology: ViewportBodyTopology,
    scene: ViewportScene,
    layout: ViewportLayout,
    selectionHitPolicy: ViewportSelectionHitPolicy = .all
) -> (edge: ViewportBodyTopology.Edge, point: CGPoint)? {
    let tester = ViewportHitTester()
    for edge in topology.edges {
        for ratio in [0.5, 0.35, 0.65] {
            let point = Point3D(
                x: edge.start.x + (edge.end.x - edge.start.x) * ratio,
                y: edge.start.y + (edge.end.y - edge.start.y) * ratio,
                z: edge.start.z + (edge.end.z - edge.start.z) * ratio
            )
            let projectedPoint = layout.project(point)
            let hit = tester.hitTest(
                point: projectedPoint,
                in: scene,
                layout: layout,
                selectionHitPolicy: selectionHitPolicy
            )
            if hit?.selectionComponent == .edge(edge.componentID) {
                return (edge, projectedPoint)
            }
        }
    }
    return nil
}

private func generatedFaceHitTarget(
    in topology: ViewportBodyTopology,
    scene: ViewportScene,
    layout: ViewportLayout,
    tolerance: CGFloat = 8.0
) -> (face: ViewportBodyTopology.Face, point: CGPoint)? {
    let tester = ViewportHitTester(tolerance: tolerance)
    for face in topology.faces {
        guard face.points.count >= 3 else {
            continue
        }
        for point in generatedFaceCandidatePoints(face.points, layout: layout) {
            let hit = tester.hitTest(point: point, in: scene, layout: layout)
            if hit?.selectionComponent == .face(face.componentID) {
                return (face, point)
            }
        }
    }
    return nil
}

private func generatedFaceCandidatePoints(
    _ points: [Point3D],
    layout: ViewportLayout
) -> [CGPoint] {
    let projectedPoints = points.map { layout.project($0) }
    let center = projectedCenter(of: points, layout: layout)
    var candidates = [center]
    for projectedPoint in projectedPoints {
        candidates.append(CGPoint(
            x: center.x * 0.72 + projectedPoint.x * 0.28,
            y: center.y * 0.72 + projectedPoint.y * 0.28
        ))
    }
    return candidates
}

private func viewportGeneratedTopologyScene() -> ViewportScene {
    let featureID = FeatureID()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:vertex:frontBottomLeft"
    )
    let frontBottomLeft = Point3D(x: -0.010, y: 0.0, z: -0.010)
    let frontBottomRight = Point3D(x: 0.010, y: 0.0, z: -0.010)
    let frontTopRight = Point3D(x: 0.010, y: 0.0, z: 0.010)
    let frontTopLeft = Point3D(x: -0.010, y: 0.0, z: 0.010)
    let topology = ViewportBodyTopology(
        faces: [
            ViewportBodyTopology.Face(
                componentID: faceComponentID,
                points: [
                    frontBottomLeft,
                    frontBottomRight,
                    frontTopRight,
                    frontTopLeft,
                ]
            ),
        ],
        edges: [
            ViewportBodyTopology.Edge(
                componentID: edgeComponentID,
                start: frontBottomLeft,
                end: frontBottomRight
            ),
        ],
        vertices: [
            ViewportBodyTopology.Vertex(
                componentID: vertexComponentID,
                point: frontBottomLeft
            ),
        ]
    )
    let component = ViewportBodyComponent(
        sizeXMeters: 0.020,
        sizeYMeters: 0.020,
        sizeZMeters: 0.020,
        yMinMeters: 0.0,
        yMaxMeters: 0.020,
        topology: topology
    )
    let item = ViewportSceneItem(
        id: featureID.description,
        featureID: featureID,
        modelBounds: CGRect(x: -0.010, y: -0.010, width: 0.020, height: 0.020),
        kind: .body(component: component)
    )
    return ViewportScene(items: [item])
}

private func denseGeneratedTopologyScene(columns: Int, rows: Int) -> ViewportScene {
    let featureID = FeatureID()
    let safeColumns = max(columns, 1)
    let safeRows = max(rows, 1)
    let cellSize = 0.01
    let xOffset = Double(safeColumns) * cellSize * 0.5
    let zOffset = Double(safeRows) * cellSize * 0.5
    var faces: [ViewportBodyTopology.Face] = []
    faces.reserveCapacity(safeColumns * safeRows)

    for row in 0 ..< safeRows {
        for column in 0 ..< safeColumns {
            let x0 = Double(column) * cellSize - xOffset
            let x1 = x0 + cellSize
            let z0 = Double(row) * cellSize - zOffset
            let z1 = z0 + cellSize
            faces.append(ViewportBodyTopology.Face(
                componentID: SelectionComponentID.generatedTopology(
                    "feature:body:subshape:dense:face:\(row):\(column)"
                ),
                points: [
                    Point3D(x: x0, y: 0.0, z: z0),
                    Point3D(x: x1, y: 0.0, z: z0),
                    Point3D(x: x1, y: 0.0, z: z1),
                    Point3D(x: x0, y: 0.0, z: z1),
                ]
            ))
        }
    }

    let component = ViewportBodyComponent(
        sizeXMeters: Double(safeColumns) * cellSize,
        sizeYMeters: cellSize,
        sizeZMeters: Double(safeRows) * cellSize,
        yMinMeters: 0.0,
        yMaxMeters: cellSize,
        topology: ViewportBodyTopology(faces: faces)
    )
    let item = ViewportSceneItem(
        id: featureID.description,
        featureID: featureID,
        modelBounds: CGRect(
            x: -xOffset,
            y: -zOffset,
            width: Double(safeColumns) * cellSize,
            height: Double(safeRows) * cellSize
        ),
        kind: .body(component: component)
    )
    return ViewportScene(items: [item])
}

private struct OverlappingGeneratedFaceScene {
    var scene: ViewportScene
    var nearCenter: Point3D
    var nearFeatureID: FeatureID
    var nearFaceComponentID: SelectionComponentID
}

private struct OverlappingGeneratedPrimitiveComponent {
    var modelBounds: CGRect
    var nearCenter: Point3D
    var item: ViewportSceneItem
    var vertexComponent: ViewportBodyComponent
    var edgeComponent: ViewportBodyComponent
    var faceComponent: ViewportBodyComponent
    var nearVertexComponentID: SelectionComponentID
    var nearEdgeComponentID: SelectionComponentID
    var nearFaceComponentID: SelectionComponentID
}

private func overlappingGeneratedFaceScene() throws -> OverlappingGeneratedFaceScene {
    let basis = ViewportProjectionBasis.isometric
    let centers = try overlappingDepthCenters(basis: basis)
    let farFeatureID = FeatureID()
    let nearFeatureID = FeatureID()
    let farFaceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:face:far"
    )
    let nearFaceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:face:near"
    )
    let farFace = ViewportBodyTopology.Face(
        componentID: farFaceComponentID,
        points: screenPlaneFacePoints(center: centers.far, basis: basis)
    )
    let nearFace = ViewportBodyTopology.Face(
        componentID: nearFaceComponentID,
        points: screenPlaneFacePoints(center: centers.near, basis: basis)
    )
    let farItem = viewportBodyItem(
        featureID: farFeatureID,
        topology: ViewportBodyTopology(faces: [farFace]),
        points: farFace.points
    )
    let nearItem = viewportBodyItem(
        featureID: nearFeatureID,
        topology: ViewportBodyTopology(faces: [nearFace]),
        points: nearFace.points
    )
    return OverlappingGeneratedFaceScene(
        scene: ViewportScene(items: [farItem, nearItem]),
        nearCenter: centers.near,
        nearFeatureID: nearFeatureID,
        nearFaceComponentID: nearFaceComponentID
    )
}

private func overlappingGeneratedPrimitiveComponent() throws -> OverlappingGeneratedPrimitiveComponent {
    let basis = ViewportProjectionBasis.isometric
    let centers = try overlappingDepthCenters(basis: basis)
    let farVertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:vertex:far"
    )
    let nearVertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:vertex:near"
    )
    let farEdgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:edge:far"
    )
    let nearEdgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:edge:near"
    )
    let farFaceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:face:far"
    )
    let nearFaceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:test:face:near"
    )
    let farFacePoints = screenPlaneFacePoints(center: centers.far, basis: basis)
    let nearFacePoints = screenPlaneFacePoints(center: centers.near, basis: basis)
    let farEdge = screenPlaneEdgePoints(center: centers.far, basis: basis)
    let nearEdge = screenPlaneEdgePoints(center: centers.near, basis: basis)
    let allPoints = farFacePoints + nearFacePoints

    return OverlappingGeneratedPrimitiveComponent(
        modelBounds: modelBounds(for: allPoints),
        nearCenter: centers.near,
        item: viewportBodyItem(
            featureID: FeatureID(),
            topology: ViewportBodyTopology(),
            points: allPoints
        ),
        vertexComponent: viewportBodyComponent(
            topology: ViewportBodyTopology(
                vertices: [
                    ViewportBodyTopology.Vertex(
                        componentID: farVertexComponentID,
                        point: centers.far
                    ),
                    ViewportBodyTopology.Vertex(
                        componentID: nearVertexComponentID,
                        point: centers.near
                    ),
                ]
            ),
            points: [centers.far, centers.near]
        ),
        edgeComponent: viewportBodyComponent(
            topology: ViewportBodyTopology(
                edges: [
                    ViewportBodyTopology.Edge(
                        componentID: farEdgeComponentID,
                        start: farEdge.start,
                        end: farEdge.end
                    ),
                    ViewportBodyTopology.Edge(
                        componentID: nearEdgeComponentID,
                        start: nearEdge.start,
                        end: nearEdge.end
                    ),
                ]
            ),
            points: [farEdge.start, farEdge.end, nearEdge.start, nearEdge.end]
        ),
        faceComponent: viewportBodyComponent(
            topology: ViewportBodyTopology(
                faces: [
                    ViewportBodyTopology.Face(
                        componentID: farFaceComponentID,
                        points: farFacePoints
                    ),
                    ViewportBodyTopology.Face(
                        componentID: nearFaceComponentID,
                        points: nearFacePoints
                    ),
                ]
            ),
            points: allPoints
        ),
        nearVertexComponentID: nearVertexComponentID,
        nearEdgeComponentID: nearEdgeComponentID,
        nearFaceComponentID: nearFaceComponentID
    )
}

private func overlappingDepthCenters(
    basis: ViewportProjectionBasis
) throws -> (far: Point3D, near: Point3D) {
    let normal = try #require(basis.viewNormal)
    let offset = 0.006
    return (
        far: Point3D(
            x: -normal.x * offset,
            y: -normal.y * offset,
            z: -normal.z * offset
        ),
        near: Point3D(
            x: normal.x * offset,
            y: normal.y * offset,
            z: normal.z * offset
        )
    )
}

private func screenPlaneFacePoints(
    center: Point3D,
    basis: ViewportProjectionBasis
) -> [Point3D] {
    let half = 0.008
    return [
        screenPlanePoint(center: center, basis: basis, u: -half, v: -half),
        screenPlanePoint(center: center, basis: basis, u: half, v: -half),
        screenPlanePoint(center: center, basis: basis, u: half, v: half),
        screenPlanePoint(center: center, basis: basis, u: -half, v: half),
    ]
}

private func screenPlaneEdgePoints(
    center: Point3D,
    basis: ViewportProjectionBasis
) -> (start: Point3D, end: Point3D) {
    let half = 0.008
    return (
        start: screenPlanePoint(center: center, basis: basis, u: -half, v: 0.0),
        end: screenPlanePoint(center: center, basis: basis, u: half, v: 0.0)
    )
}

private func screenPlanePoint(
    center: Point3D,
    basis: ViewportProjectionBasis,
    u: Double,
    v: Double
) -> Point3D {
    Point3D(
        x: center.x + Double(basis.xDirection.dx) * u + Double(basis.xDirection.dy) * v,
        y: center.y + Double(basis.yDirection.dx) * u + Double(basis.yDirection.dy) * v,
        z: center.z + Double(basis.zDirection.dx) * u + Double(basis.zDirection.dy) * v
    )
}

private func viewportBodyItem(
    featureID: FeatureID,
    topology: ViewportBodyTopology,
    points: [Point3D]
) -> ViewportSceneItem {
    ViewportSceneItem(
        id: featureID.description,
        featureID: featureID,
        modelBounds: modelBounds(for: points),
        kind: .body(component: viewportBodyComponent(topology: topology, points: points))
    )
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

private func viewportBodyComponent(
    topology: ViewportBodyTopology,
    points: [Point3D]
) -> ViewportBodyComponent {
    let xValues = points.map(\.x)
    let yValues = points.map(\.y)
    let zValues = points.map(\.z)
    let minX = xValues.min() ?? 0.0
    let maxX = xValues.max() ?? 0.001
    let minY = yValues.min() ?? 0.0
    let maxY = yValues.max() ?? 0.001
    let minZ = zValues.min() ?? 0.0
    let maxZ = zValues.max() ?? 0.001
    return ViewportBodyComponent(
        sizeXMeters: max(maxX - minX, 1.0e-9),
        sizeYMeters: max(maxY - minY, 1.0e-9),
        sizeZMeters: max(maxZ - minZ, 1.0e-9),
        yMinMeters: minY,
        yMaxMeters: maxY,
        topology: topology
    )
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
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        x, y, z, 1.0,
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

private func pointIsApproximatelyEqual(
    _ lhs: Point2D,
    _ rhs: Point2D,
    tolerance: Double = 1.0e-12
) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}
