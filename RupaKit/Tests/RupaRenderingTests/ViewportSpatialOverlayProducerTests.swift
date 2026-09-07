import CoreGraphics
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test
func nativePolygonFillPreservesConcavityAndRejectsDegenerateInput() throws {
    let polygon = [
        Point3D(x: 0, y: 2, z: 0), Point3D(x: 3, y: 2, z: 0),
        Point3D(x: 3, y: 2, z: 1), Point3D(x: 1, y: 2, z: 1),
        Point3D(x: 1, y: 2, z: 3), Point3D(x: 0, y: 2, z: 3),
    ]
    let fill = try ViewportSpatialOverlayProducer.polygonFill(polygon, color: [1, 1, 0, 1])
    #expect(fill.origin == polygon[0])
    #expect(fill.path.contains(CGPoint(x: 0.5, y: 2)))
    #expect(!fill.path.contains(CGPoint(x: 2, y: 2)))
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.polygonFill(
            [.origin, .origin, .origin], color: [1, 1, 0, 1]
        )
    }
}

@Test
func combinedRawAffordancesFitTheNativeGridBudgetForASelectedBody() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let document = session.document
    let ruler = session.workspaceState.ruler
    let scene = ViewportSceneBuilder().build(document: document, ruler: ruler)
    let body = try #require(scene.items.first { if case .body = $0.kind { return true }; return false })
    let node = try #require(body.sceneNodeID)
    let target = SelectionTarget(sceneNodeID: node)
    let selection = SelectionModel(selectedTargets: [target])
    let snapshot = ViewportSpatialOverlaySemanticSnapshot(
        scene: scene,
        interaction: .init(
            selectedFeatureIDs: [body.featureID], selectedSceneNodeIDs: [node],
            hoveredFeatureIDs: [], hoveredSceneNodeIDs: [], selectedTargets: [target],
            objectSelectionTargets: [target], selectedSketchEntities: [], previewSketchEntities: [],
            hoveredSketchEntity: nil, selectedSketchRegions: [], previewSketchRegions: [], hoveredSketchRegion: nil
        ),
        sketchCurveSource: .init(document: document, scene: scene, selection: selection, ruler: ruler),
        surfaceTransformSource: .init(document: document, scene: scene, selection: selection, ruler: ruler),
        patternSource: .init(document: document, scene: scene, selection: selection, ruler: ruler, hasRoute: true),
        editedBodies: [:], world: .init(modelBounds: body.modelBounds),
        includesGrid: true, measurement: nil, drawsLegacyBodies: true, drawsDragPreviewBodies: false
    )
    let builder = ViewportSpatialOverlayProducer.makeBuilder(from: snapshot, topologyRevision: 1)
    let output = try await Task.detached { try builder(.origin, 0) }.value
    #expect(output.spatialBatch.includesGrid)
    #expect(output.spatialBatch.handleCount == output.handleIdentities.count)
    #expect(output.handleIdentities.contains {
        if case .affordance = $0 { return true }; return false
    })
    #expect(!output.spatialBatch.meshes.isEmpty)
}

@Test
func nativeSectionKeepsOpenContoursUnfilledAndUnclosed() throws {
    let start = Point3D(x: 1, y: 0, z: 2)
    let end = Point3D(x: 3, y: 0, z: 4)
    let section = ViewportSpatialOverlaySemanticSnapshot.Section(
        plane: nil, segments: [.init(start: start, end: end)],
        contours: [.init(points: [start, end], isClosed: false)], hatches: [],
        sourceSegmentCount: 1, omittedSegmentCount: 0,
        sourceContourCount: 1, omittedContourCount: 0, hasTruncatedSourcePayload: false
    )
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSection(
        section, paths: &paths, meshes: &meshes, activeFamilies: &families
    )
    #expect(paths.isEmpty)
    #expect(meshes.count == 1)
    #expect(meshes[0].value.positions == [start, end])
    #expect(meshes[0].value.indices == [0, 1])
    #expect(families == [.section])
}

@Test
func spatialOverlayProducerRejectsAnActiveFamilyWithoutDescriptors() {
    let input = ViewportSpatialOverlayInput(
        activeFamilies: [.measurement],
        renderOrigin: .origin,
        retainedSurfaceByteCount: 0,
        topologyRevision: 1
    )

    do {
        _ = try ViewportSpatialOverlayProducer.makeBatch(from: input)
        Issue.record("An active spatial family published an empty batch.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .invalidSceneItem)
    } catch {
        Issue.record("Unexpected spatial producer error: \(error)")
    }
}

@Test
func spatialOverlayProducerPreservesWorldPointsAndSemanticAttachment() throws {
    let mesh = RealityViewportSpatialBatch.Mesh(
        positions: [
            Point3D(x: 10, y: 1, z: -2),
            Point3D(x: 11, y: 1, z: -2),
        ],
        indices: [0, 1],
        topology: .lines,
        color: [1, 0, 0, 1]
    )
    let input = ViewportSpatialOverlayInput(
        activeFamilies: [.curve],
        meshes: [.init(family: .curve, value: mesh)],
        renderOrigin: Point3D(x: 9, y: 1, z: -3),
        retainedSurfaceByteCount: 0,
        topologyRevision: 12
    )

    let batch = try ViewportSpatialOverlayProducer.makeBatch(from: input)
    #expect(batch.meshes.count == 1)
    #expect(batch.meshes[0].positions == mesh.positions)
    #expect(batch.renderOrigin == input.renderOrigin)
    #expect({
        if case .sectionedGeometry = batch.meshes[0].attachment { return true }
        return false
    }())
}

@Test
func spatialOverlayProducerRefusesCompleteInputInsteadOfPrefixTruncating() {
    let markers = (0 ... 640).map { index in
        ViewportSpatialOverlayInput.Marker(
            family: .measurement,
            value: .init(
                shape: .sphere,
                anchor: Point3D(x: Double(index), y: 0, z: 0),
                diameterPoints: 6,
                color: [0, 1, 1, 1]
            )
        )
    }
    let input = ViewportSpatialOverlayInput(
        activeFamilies: [.measurement],
        markers: markers,
        renderOrigin: .origin,
        retainedSurfaceByteCount: 0,
        topologyRevision: 7
    )

    do {
        _ = try ViewportSpatialOverlayProducer.makeBatch(from: input)
        Issue.record("Over-budget markers were silently truncated or accepted.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    } catch {
        Issue.record("Unexpected spatial producer error: \(error)")
    }
}

@Test
func spatialOverlayProducerKeepsVisibleCellPlacementCameraIndependent() throws {
    let placement = RealityViewportSpatialBatch.GridPlacement(
        center: Point3D(x: 0.25, y: 0.0, z: -0.5),
        uAxis: SIMD3<Double>(1, 0, 0),
        vAxis: SIMD3<Double>(0, 0, 1),
        widthMeters: nil,
        heightMeters: 0.12,
        color: [0.25, 0.92, 1.0, 1.0]
    )
    let input = ViewportSpatialOverlayInput(
        activeFamilies: [.placement],
        gridPlacement: placement,
        includesGrid: true,
        renderOrigin: .origin,
        retainedSurfaceByteCount: 0,
        topologyRevision: 1
    )

    let batch = try ViewportSpatialOverlayProducer.makeBatch(from: input)
    #expect(batch.gridPlacement?.center == placement.center)
    #expect(batch.gridPlacement?.widthMeters == nil)
    #expect(batch.gridPlacement?.heightMeters == 0.12)
    #expect(batch.includesGrid)
    #expect(batch.meshes.isEmpty)
}

@Test
func semanticDragPreviewDoesNotRejectAnUnmovedCreationPress() throws {
    let drag = ViewportModelDrag(
        start: Point2D(x: 0.0, y: 0.0),
        end: Point2D(x: 0.0, y: 0.0),
        sketchPlane: .xy,
        startWorldPoint: .origin,
        endWorldPoint: .origin,
        startViewRayAnchorWorldPoint: .origin,
        endViewRayAnchorWorldPoint: .origin
    )
    let snapshot = ViewportSpatialOverlaySemanticSnapshot(
        scene: ViewportScene(items: []),
        interaction: .init(
            selectedFeatureIDs: [],
            selectedSceneNodeIDs: [],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        editedBodies: [:],
        world: .init(modelBounds: .zero),
        dragPreview: .init(
            kind: .rectangle(widthMeters: nil, heightMeters: nil),
            drag: drag,
            document: .empty(),
            ruler: .standard(for: .meter),
            snapOptions: nil,
            axisConstraint: nil
        ),
        measurement: nil,
        drawsLegacyBodies: false,
        drawsDragPreviewBodies: false
    )

    let input = try ViewportSpatialOverlayProducer.makeInput(
        from: snapshot,
        renderOrigin: .origin,
        retainedSurfaceByteCount: 0,
        topologyRevision: 1
    )
    #expect(!input.activeFamilies.contains(.placement))
    #expect(!input.meshes.contains { $0.family == .placement })
}

@Test
func semanticSnapshotBuilderCanPrepareOffMainActorWithoutChangingWorldGeometry() async throws {
    let featureID = FeatureID()
    let item = ViewportSceneItem(
        id: "snapshot-body",
        featureID: featureID,
        modelBounds: CGRect(x: -1, y: -2, width: 2, height: 4),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 4,
            sizeZMeters: 3,
            yMinMeters: 0,
            yMaxMeters: 3
        ))
    )
    let rulerBounds = try GeometryBounds3D(
        minimum: GeometryPoint3D(x: -1, y: 0, z: -2),
        maximum: GeometryPoint3D(x: 1, y: 3, z: 2)
    )
    let snapshot = ViewportSpatialOverlaySemanticSnapshot(
        scene: ViewportScene(items: [item]),
        interaction: .init(
            selectedFeatureIDs: [],
            selectedSceneNodeIDs: [],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        editedBodies: [featureID: .init(xMin: 5, xMax: 7, yMin: 1, yMax: 4, zMin: -2, zMax: 2)],
        world: .init(
            modelBounds: item.modelBounds
        ),
        measurement: .init(
            start: nil,
            end: nil,
            label: nil,
            boundsRuler: .init(
                bounds: rulerBounds,
                labels: .init(x: "World bounds X: 2 m", y: "World bounds Y: 3 m", z: "World bounds Z: 4 m")
            )
        ),
        drawsLegacyBodies: true,
        drawsDragPreviewBodies: false
    )
    let builder = ViewportSpatialOverlayProducer.makeBuilder(
        from: snapshot,
        topologyRevision: 1
    )

    let first = try await Task.detached {
        try builder(Point3D.origin, 0).spatialBatch
    }.value
    let shiftedOrigin = Point3D(x: 10, y: -4, z: 2)
    let second = try await Task.detached {
        try builder(shiftedOrigin, 0).spatialBatch
    }.value

    #expect(first.renderOrigin == .origin)
    #expect(second.renderOrigin == shiftedOrigin)
    #expect(first.meshes.count == second.meshes.count)
    #expect(first.meshes.first?.positions == second.meshes.first?.positions)
    let input = try ViewportSpatialOverlayProducer.makeInput(
        from: snapshot, renderOrigin: .origin, retainedSurfaceByteCount: 0, topologyRevision: 1
    )
    let editedBodyMeshes = input.meshes.filter { $0.family == .body }
    #expect(editedBodyMeshes.count == 6)
    #expect(editedBodyMeshes.allSatisfy { $0.value.positions.allSatisfy { (5 ... 7).contains($0.x) } })
    #expect(first.meshes.contains {
        if case .sectionedGeometry = $0.attachment { return true }
        return false
    })
    #expect(first.boundsRulers.map { _ in true } ?? false)
}

@Test
func semanticSnapshotBuilderBatchesBodyTrianglesIntoOneIndexedDescriptor() throws {
    let triangleCount = 641
    let positionCount = triangleCount * 3
    let sourcePositions = (0 ..< positionCount).map { index in
        Point3D(
            x: Double(index % 3) * 0.25,
            y: Double((index / 3) % 3) * 0.25,
            z: Double(index) * 1.0e-6
        )
    }
    let sourceIndices = (0 ..< positionCount).map { UInt32($0) }
    let transform = Transform3D(matrix: try Matrix4x4(values: [
        2.0, 0.0, 0.0, 10.0,
        0.0, 2.0, 0.0, -3.0,
        0.0, 0.0, 2.0, 0.5,
        0.0, 0.0, 0.0, 1.0,
    ]))
    let item = ViewportSceneItem(
        id: "large-body",
        featureID: FeatureID(),
        modelTransform: transform,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 2,
            sizeZMeters: 2,
            yMinMeters: -1,
            yMaxMeters: 1,
            mesh: ViewportBodyMesh(
                positions: sourcePositions,
                indices: sourceIndices
            )
        ))
    )
    let snapshot = ViewportSpatialOverlaySemanticSnapshot(
        scene: ViewportScene(items: [item]),
        interaction: .init(
            selectedFeatureIDs: [],
            selectedSceneNodeIDs: [],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        editedBodies: [:],
        world: .init(modelBounds: item.modelBounds),
        measurement: nil,
        drawsLegacyBodies: true,
        drawsDragPreviewBodies: false
    )

    let builder = ViewportSpatialOverlayProducer.makeBuilder(
        from: snapshot,
        topologyRevision: 3
    )
    let batch = try builder(.origin, 0).spatialBatch
    let bodyMeshes = batch.meshes.filter { mesh in
        guard case .sectionedGeometry = mesh.attachment,
              case .triangles = mesh.topology else {
            return false
        }
        return true
    }

    #expect(bodyMeshes.count == 1)
    let bodyMesh = try #require(bodyMeshes.first)
    #expect(bodyMesh.positions == sourcePositions.map {
        ViewportLayout.transformedPoint($0, by: transform)
    })
    #expect(bodyMesh.indices == sourceIndices)
    #expect(batch.triangleCount == triangleCount)
    #expect(batch.itemCount < triangleCount)
}

@Test
func semanticSnapshotBuilderEmitsSelectionPatternAnalysisAndSectionFamilies() throws {
    let featureID = FeatureID()
    let rootSceneNodeID = SceneNodeID()
    let patternSourceID = PatternArraySourceID()
    let sceneNode = SceneNode(
        id: rootSceneNodeID,
        name: "Pattern Root",
        reference: .body(featureID)
    )
    let patternSource = PatternArraySource(
        id: patternSourceID,
        name: "Array",
        definitionID: ComponentDefinitionID(),
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(1.0, .meter),
                copyCount: 2
            )
        )),
        outputMode: .independentCopy,
        outputSceneNodeIDs: [rootSceneNodeID],
        rootSceneNodeID: rootSceneNodeID
    )
    var document = DesignDocument.empty()
    document.productMetadata = ProductMetadata(
        sceneNodes: [rootSceneNodeID: sceneNode],
        rootSceneNodeIDs: [rootSceneNodeID],
        patternArrays: [patternSourceID: patternSource]
    )

    let item = ViewportSceneItem(
        id: "pattern-source",
        featureID: featureID,
        sceneNodeID: rootSceneNodeID,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 2,
            sizeZMeters: 2,
            yMinMeters: -1,
            yMaxMeters: 1
        ))
    )
    let scene = ViewportScene(items: [item])
    let target = SelectionTarget(sceneNodeID: rootSceneNodeID)
    let modelSelection = SelectionModel(selectedTargets: [target])

    let snapshotID = EvaluationSnapshotID(
        projectID: ProjectID(rawValue: "project.native-overlays"),
        purpose: .presentation,
        sourceRevision: DocumentTransactionRevision(1)
    )
    let geometrySourceID = GeometrySourceID(rawValue: "mesh.native-overlays")
    let vertex = MeshVertexID(0)
    let point = ViewportMeshSelectionOverlay.Point(
        element: .vertex(vertex),
        vertexID: vertex,
        sourcePosition: GeometryPoint3D(x: 0, y: 0, z: 0),
        position: GeometryPoint3D(x: 0, y: 1, z: 0)
    )
    let selectionOverlay = ViewportMeshSelectionOverlay(
        snapshotID: snapshotID,
        sourceReference: .authoredMesh(geometrySourceID),
        sourceID: geometrySourceID,
        occurrenceID: SceneOccurrenceID(rawValue: "occurrence.native-overlays"),
        selectedElements: [.vertex(vertex)],
        points: [point],
        boundarySegments: [],
        sourceBoundarySegmentCount: 0,
        visibleBoundarySegmentCount: 0,
        isTruncated: false
    )

    let analysisFace = SurfaceAnalysisResult.FaceAnalysis(
        faceID: "face.native-overlays",
        sourceFeatureID: featureID.description,
        sceneNodeID: rootSceneNodeID.description,
        uDegree: 1,
        vDegree: 1,
        uControlPointCount: 2,
        vControlPointCount: 2,
        uDomain: .init(lowerBound: 0, upperBound: 1),
        vDomain: .init(lowerBound: 0, upperBound: 1),
        samples: [],
        curvatureCombs: [.init(
            direction: .u,
            u: 0.5,
            v: 0.5,
            position: .init(x: 0, y: 0, z: 0),
            normal: .init(x: 0, y: 1, z: 0),
            neighborDistance: 1,
            normalAngle: 0,
            normalChangePerLength: 0.2,
            normalCurvature: 1
        )],
        maxUNormalChangePerLength: 0.2,
        maxVNormalChangePerLength: 0,
        maxNormalAngle: 0,
        maxAbsUNormalCurvature: 1,
        maxAbsVNormalCurvature: 0,
        maxAbsPrincipalCurvature: 0,
        maxAbsGaussianCurvature: 0
    )
    let analysisResult = SurfaceAnalysisResult(
        displayUnit: .meter,
        faces: [analysisFace]
    )
    let sectionResult = SectionAnalysisResult(
        displayUnit: .meter,
        plane: .init(
            sourceKind: .sketchPlane,
            sourceID: nil,
            sourceName: "Section",
            origin: .origin,
            normal: .unitY,
            u: .unitX,
            v: .unitZ
        ),
        toleranceMeters: 1.0e-6,
        bodies: [],
        intersectionSegments: [.init(
            bodyID: "body.native-overlays",
            start: Point3D(x: -1, y: 0, z: 0),
            end: Point3D(x: 1, y: 0, z: 0),
            start2D: Point2D(x: -1, y: 0),
            end2D: Point2D(x: 1, y: 0)
        )],
        intersectionContours: [.init(
            id: "contour.native-overlays",
            bodyID: "body.native-overlays",
            points: [
                Point3D(x: -1, y: 0, z: -1),
                Point3D(x: 1, y: 0, z: -1),
                Point3D(x: 1, y: 0, z: 1),
            ],
            points2D: [
                Point2D(x: -1, y: -1),
                Point2D(x: 1, y: -1),
                Point2D(x: 1, y: 1),
            ],
            isClosed: true,
            signedAreaSquareMeters: 4,
            lengthMeters: 8,
            segmentCount: 3
        )],
        truncatedIntersectionSegments: false,
        diagnostics: []
    )

    let interaction = ViewportSpatialOverlaySemanticSnapshot.Interaction(
        selectedFeatureIDs: [featureID],
        selectedSceneNodeIDs: [rootSceneNodeID],
        hoveredFeatureIDs: [],
        hoveredSceneNodeIDs: [],
        selectedTargets: [target],
        selectedSketchEntities: [],
        previewSketchEntities: [],
        hoveredSketchEntity: nil,
        selectedSketchRegions: [],
        previewSketchRegions: [],
        hoveredSketchRegion: nil
    )
    let snapshot = ViewportSpatialOverlaySemanticSnapshot(
        scene: scene,
        interaction: interaction,
        meshSelection: selectionOverlay,
        patternSource: .init(
            document: document,
            scene: scene,
            selection: modelSelection,
            hasRoute: true,
            replacementRequest: nil
        ),
        analysisSource: .init(
            result: analysisResult,
            continuity: nil,
            scene: scene,
            selection: modelSelection,
            document: document,
            options: .init()
        ),
        sectionSource: .init(
            result: sectionResult,
            ruler: .standard(for: .meter)
        ),
        editedBodies: [:],
        world: .init(modelBounds: item.modelBounds),
        measurement: nil,
        drawsLegacyBodies: true,
        drawsDragPreviewBodies: false
    )

    let input = try ViewportSpatialOverlayProducer.makeInput(
        from: snapshot,
        renderOrigin: .origin,
        retainedSurfaceByteCount: 0,
        topologyRevision: 4
    )
    #expect(input.activeFamilies.contains(.meshSelection))
    #expect(input.activeFamilies.contains(.pattern))
    #expect(input.activeFamilies.contains(.analysis))
    #expect(input.activeFamilies.contains(.section))
    #expect(input.paths.filter { $0.family == .section }.count == 2)
    #expect(input.markers.contains { $0.family == .meshSelection })
    #expect(input.labels.contains { $0.value.text == "Array #1" })
    #expect(input.meshes.contains { $0.family == .analysis })
    #expect(input.meshes.contains { $0.family == .section })
    #expect(input.meshes.contains { mesh in
        mesh.family == .pattern
            && mesh.value.positions.contains(Point3D(x: 1, y: 0, z: 1))
    })
}

@Test
func semanticPatternCurveSamplingAndPlanningRunOffMainActor() async throws {
    let validSnapshot = makeCurvePatternSnapshot(
        path: .polyline(
            points: [
                .origin,
                Point3D(x: 0.1, y: 0, z: 0),
            ],
            normal: .unitZ
        ),
        includesReplacementPreview: true
    )
    let validInput = try await Task.detached {
        try ViewportSpatialOverlayProducer.makeInput(
            from: validSnapshot,
            renderOrigin: .origin,
            retainedSurfaceByteCount: 0,
            topologyRevision: 5
        )
    }.value
    #expect(validInput.activeFamilies.contains(.pattern))
    #expect(validInput.meshes.contains { $0.family == .pattern })
    #expect(validInput.markers.contains { $0.family == .pattern })
    #expect(validInput.labels.contains { $0.family == .pattern })

    let invalidSnapshot = makeCurvePatternSnapshot(
        path: .polyline(
            points: [.origin],
            normal: .unitZ
        )
    )
    do {
        _ = try await Task.detached {
            try ViewportSpatialOverlayProducer.makeInput(
                from: invalidSnapshot,
                renderOrigin: .origin,
                retainedSurfaceByteCount: 0,
                topologyRevision: 6
            )
        }.value
        Issue.record("An invalid curve pattern path was accepted by the worker.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .invalidSceneItem)
    } catch {
        Issue.record("Unexpected curve pattern worker error: \(error)")
    }
}

@Test
func semanticProducerRejectsAnAlreadyCancelledTaskBeforeMaterialization() async {
    let snapshot = makeCurvePatternSnapshot(
        path: .polyline(
            points: [
                .origin,
                Point3D(x: 0.1, y: 0, z: 0),
            ],
            normal: .unitZ
        )
    )
    let task = Task.detached { () throws -> ViewportSpatialOverlayInput in
        withUnsafeCurrentTask { $0?.cancel() }
        return try ViewportSpatialOverlayProducer.makeInput(
            from: snapshot,
            renderOrigin: .origin,
            retainedSurfaceByteCount: 0,
            topologyRevision: 7
        )
    }

    do {
        _ = try await task.value
        Issue.record("An already-cancelled semantic producer task was accepted.")
    } catch is CancellationError {
        // Expected: cancellation is observed before any source materialization.
    } catch {
        Issue.record("Unexpected cancellation error: \(error)")
    }
}

@Test
func semanticProducerRefusesAnOverLimitPatternBeforePreviewMaterialization() {
    let snapshot = makePatternBudgetSnapshot(outputCount: 321)
    do {
        _ = try ViewportSpatialOverlayProducer.makeInput(
            from: snapshot,
            renderOrigin: .origin,
            retainedSurfaceByteCount: 0,
            topologyRevision: 8
        )
        Issue.record("An over-limit pattern source was materialized.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    } catch {
        Issue.record("Unexpected pattern admission error: \(error)")
    }
}

@Test
func semanticProducerRefusesAnOverLimitAnalysisBeforeOverlayMaterialization() {
    let snapshot = makeAnalysisBudgetSnapshot(curvatureCount: 641)
    do {
        _ = try ViewportSpatialOverlayProducer.makeInput(
            from: snapshot,
            renderOrigin: .origin,
            retainedSurfaceByteCount: 0,
            topologyRevision: 9
        )
        Issue.record("An over-limit analysis source was materialized.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    } catch {
        Issue.record("Unexpected analysis admission error: \(error)")
    }
}

@Test
func semanticProducerRefusesAnOverLimitSectionBeforePrefixOrHatchMaterialization() {
    let snapshot = makeSectionBudgetSnapshot(segmentCount: 2_049)
    do {
        _ = try ViewportSpatialOverlayProducer.makeInput(
            from: snapshot,
            renderOrigin: .origin,
            retainedSurfaceByteCount: 0,
            topologyRevision: 10
        )
        Issue.record("An over-limit section source was materialized.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    } catch {
        Issue.record("Unexpected section admission error: \(error)")
    }
}

@Test
func semanticProducerIgnoresUnselectedAnalysisSamples() throws {
    let snapshot = makeAnalysisBudgetSnapshot(curvatureCount: 1, includesLargeUnselectedFace: true)
    let input = try ViewportSpatialOverlayProducer.makeInput(
        from: snapshot, renderOrigin: .origin, retainedSurfaceByteCount: 0, topologyRevision: 11
    )
    #expect(input.meshes.filter { $0.family == .analysis }.count == 1)
}

@Test
func semanticAnalysisBuilderPropagatesMidBuildCancellation() async throws {
    let source = try #require(makeAnalysisBudgetSnapshot(curvatureCount: 100).analysisSource)
    let result = try await Task.detached { () throws -> (Bool, Int) in
        var visits = 0
        do {
            _ = try ViewportSurfaceAnalysisOverlay.build(
                result: source.result, selection: source.selection, document: source.document,
                options: source.options,
                checkpoint: { _, _, count in
                    visits += count
                    if visits >= 8 { withUnsafeCurrentTask { $0?.cancel() } }
                    try Task.checkCancellation()
                }
            )
            return (false, visits)
        } catch is CancellationError {
            return (true, visits)
        }
    }.value
    #expect(result.0)
    #expect(result.1 == 8)
}

@Test
func semanticProducerRejectsOversizedSectionPlaneCoordinates() {
    let snapshot = makeSectionBudgetSnapshot(segmentCount: 0, oversizedPlaneCoordinates: true)
    do {
        _ = try ViewportSpatialOverlayProducer.makeInput(
            from: snapshot, renderOrigin: .origin, retainedSurfaceByteCount: 0, topologyRevision: 12
        )
        Issue.record("Oversized plane coordinates bypassed section admission.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .resourceExhausted)
    } catch {
        Issue.record("Unexpected section plane admission error: \(error)")
    }
}

private func makeCurvePatternSnapshot(
    path: PatternArrayCurvePath,
    includesReplacementPreview: Bool = false
) -> ViewportSpatialOverlaySemanticSnapshot {
    let featureID = FeatureID()
    let rootSceneNodeID = SceneNodeID()
    let sourceID = PatternArraySourceID()
    let sceneNode = SceneNode(
        id: rootSceneNodeID,
        name: "Curve Pattern Root",
        reference: .body(featureID)
    )
    let source = PatternArraySource(
        id: sourceID,
        name: "Curve Array",
        definitionID: ComponentDefinitionID(),
        distribution: .curve(CurvePatternArray(
            path: path,
            copyCount: 2,
            extent: .scalar(1.0),
            extentMode: .ratio
        )),
        outputMode: .independentCopy,
        outputSceneNodeIDs: [rootSceneNodeID],
        rootSceneNodeID: rootSceneNodeID
    )
    var document = DesignDocument.empty()
    document.productMetadata = ProductMetadata(
        sceneNodes: [rootSceneNodeID: sceneNode],
        rootSceneNodeIDs: [rootSceneNodeID],
        patternArrays: [sourceID: source]
    )
    let item = ViewportSceneItem(
        id: "curve-pattern-source",
        featureID: featureID,
        sceneNodeID: rootSceneNodeID,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 2,
            sizeZMeters: 2,
            yMinMeters: -1,
            yMaxMeters: 1
        ))
    )
    let scene = ViewportScene(items: [item])
    let target = SelectionTarget(sceneNodeID: rootSceneNodeID)
    return ViewportSpatialOverlaySemanticSnapshot(
        scene: scene,
        interaction: .init(
            selectedFeatureIDs: [featureID],
            selectedSceneNodeIDs: [rootSceneNodeID],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedTargets: [target],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        patternSource: .init(
            document: document,
            scene: scene,
            selection: SelectionModel(selectedTargets: [target]),
            hasRoute: true,
            replacementRequest: includesReplacementPreview
                ? .init(sourceID: sourceID, path: path, title: "Candidate Path")
                : nil
        ),
        editedBodies: [:],
        world: .init(modelBounds: item.modelBounds),
        measurement: nil,
        drawsLegacyBodies: false,
        drawsDragPreviewBodies: false
    )
}

private func makePatternBudgetSnapshot(
    outputCount: Int
) -> ViewportSpatialOverlaySemanticSnapshot {
    let featureID = FeatureID()
    let rootSceneNodeID = SceneNodeID()
    let sourceID = PatternArraySourceID()
    let rootNode = SceneNode(
        id: rootSceneNodeID,
        name: "Pattern Budget Root",
        reference: .body(featureID)
    )
    let source = PatternArraySource(
        id: sourceID,
        name: "Pattern Budget",
        definitionID: ComponentDefinitionID(),
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(1.0, .meter),
                copyCount: outputCount
            )
        )),
        outputMode: .independentCopy,
        outputSceneNodeIDs: (0 ..< outputCount).map { _ in SceneNodeID() },
        rootSceneNodeID: rootSceneNodeID
    )
    var document = DesignDocument.empty()
    document.productMetadata = ProductMetadata(
        sceneNodes: [rootSceneNodeID: rootNode],
        rootSceneNodeIDs: [rootSceneNodeID],
        patternArrays: [sourceID: source]
    )
    let item = ViewportSceneItem(
        id: "pattern-budget-source",
        featureID: featureID,
        sceneNodeID: rootSceneNodeID,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 2,
            sizeZMeters: 2,
            yMinMeters: -1,
            yMaxMeters: 1
        ))
    )
    let scene = ViewportScene(items: [item])
    let target = SelectionTarget(sceneNodeID: rootSceneNodeID)
    return ViewportSpatialOverlaySemanticSnapshot(
        scene: scene,
        interaction: .init(
            selectedFeatureIDs: [featureID],
            selectedSceneNodeIDs: [rootSceneNodeID],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedTargets: [target],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        patternSource: .init(
            document: document,
            scene: scene,
            selection: SelectionModel(selectedTargets: [target]),
            hasRoute: true,
            replacementRequest: nil
        ),
        editedBodies: [:],
        world: .init(modelBounds: item.modelBounds),
        measurement: nil,
        drawsLegacyBodies: false,
        drawsDragPreviewBodies: false
    )
}

private func makeAnalysisBudgetSnapshot(
    curvatureCount: Int,
    includesLargeUnselectedFace: Bool = false
) -> ViewportSpatialOverlaySemanticSnapshot {
    let featureID = FeatureID()
    let rootSceneNodeID = SceneNodeID()
    let rootNode = SceneNode(
        id: rootSceneNodeID,
        name: "Analysis Budget Root",
        reference: .body(featureID)
    )
    var document = DesignDocument.empty()
    document.productMetadata = ProductMetadata(
        sceneNodes: [rootSceneNodeID: rootNode],
        rootSceneNodeIDs: [rootSceneNodeID]
    )
    let item = ViewportSceneItem(
        id: "analysis-budget-source",
        featureID: featureID,
        sceneNodeID: rootSceneNodeID,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 2,
            sizeZMeters: 2,
            yMinMeters: -1,
            yMaxMeters: 1
        ))
    )
    let face = SurfaceAnalysisResult.FaceAnalysis(
        faceID: "analysis-budget-face",
        sourceFeatureID: featureID.description,
        sceneNodeID: rootSceneNodeID.description,
        uDegree: 1,
        vDegree: 1,
        uControlPointCount: 2,
        vControlPointCount: 2,
        uDomain: .init(lowerBound: 0, upperBound: 1),
        vDomain: .init(lowerBound: 0, upperBound: 1),
        samples: [],
        curvatureCombs: (0 ..< curvatureCount).map { index in
            .init(
                direction: .u,
                u: Double(index) / Double(max(curvatureCount - 1, 1)),
                v: 0.5,
                position: .init(x: Double(index) * 1.0e-4, y: 0, z: 0),
                normal: .init(x: 0, y: 1, z: 0),
                neighborDistance: 1,
                normalAngle: 0,
                normalChangePerLength: 0.2,
                normalCurvature: 1
            )
        },
        maxUNormalChangePerLength: 0.2,
        maxVNormalChangePerLength: 0,
        maxNormalAngle: 0,
        maxAbsUNormalCurvature: 1,
        maxAbsVNormalCurvature: 0,
        maxAbsPrincipalCurvature: 0,
        maxAbsGaussianCurvature: 0
    )
    var faces = [face]
    if includesLargeUnselectedFace {
        var unselected = face
        unselected.faceID = "unselected-analysis-face"
        unselected.sourceFeatureID = FeatureID().description
        unselected.curvatureCombs = Array(repeating: face.curvatureCombs[0],
                                         count: MeshSourcePresentationPlanLimits.standard.maxPositionCount + 1)
        faces.append(unselected)
    }
    let scene = ViewportScene(items: [item])
    let target = SelectionTarget(sceneNodeID: rootSceneNodeID)
    return ViewportSpatialOverlaySemanticSnapshot(
        scene: scene,
        interaction: .init(
            selectedFeatureIDs: [featureID],
            selectedSceneNodeIDs: [rootSceneNodeID],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedTargets: [target],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        analysisSource: .init(
            result: .init(displayUnit: .meter, faces: faces),
            continuity: nil,
            scene: scene,
            selection: SelectionModel(selectedTargets: [target]),
            document: document,
            options: .init(
                showsCurvatureCombs: true,
                showsPrincipalDirections: false,
                showsTrimBoundaries: false
            )
        ),
        editedBodies: [:],
        world: .init(modelBounds: item.modelBounds),
        measurement: nil,
        drawsLegacyBodies: false,
        drawsDragPreviewBodies: false
    )
}

private func makeSectionBudgetSnapshot(
    segmentCount: Int,
    oversizedPlaneCoordinates: Bool = false
) -> ViewportSpatialOverlaySemanticSnapshot {
    var result = SectionAnalysisResult(
        displayUnit: .meter,
        plane: .init(
            sourceKind: .sketchPlane,
            sourceID: nil,
            sourceName: "Section Budget",
            origin: .origin,
            normal: .unitY,
            u: .unitX,
            v: .unitZ
        ),
        toleranceMeters: 1.0e-6,
        bodies: [],
        intersectionSegments: (0 ..< segmentCount).map { index in
            .init(
                bodyID: "section-budget-body",
                start: Point3D(x: Double(index), y: 0, z: 0),
                end: Point3D(x: Double(index) + 1, y: 0, z: 0),
                start2D: Point2D(x: Double(index), y: 0),
                end2D: Point2D(x: Double(index) + 1, y: 0)
            )
        },
        intersectionContours: [],
        truncatedIntersectionSegments: false,
        diagnostics: []
    )
    if oversizedPlaneCoordinates {
        result.intersectionContours = [.init(
            id: "oversized-section", bodyID: "section-budget-body",
            points: [.origin, .init(x: 1, y: 0, z: 0), .init(x: 0, y: 0, z: 1)],
            points2D: Array(repeating: .init(x: 0, y: 0),
                            count: MeshSourcePresentationPlanLimits.standard.maxPositionCount + 1),
            isClosed: true, signedAreaSquareMeters: 1, lengthMeters: 3, segmentCount: 3
        )]
    }
    return ViewportSpatialOverlaySemanticSnapshot(
        scene: ViewportScene(items: []),
        interaction: .init(
            selectedFeatureIDs: [],
            selectedSceneNodeIDs: [],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        sectionSource: .init(
            result: result,
            ruler: .standard(for: .meter)
        ),
        editedBodies: [:],
        world: .init(modelBounds: .zero),
        measurement: nil,
        drawsLegacyBodies: false,
        drawsDragPreviewBodies: false
    )
}

@Test
func semanticSnapshotBuilderRefusesMalformedWorldSourceOffMainActor() async {
    let item = ViewportSceneItem(
        id: "malformed-sketch",
        featureID: FeatureID(),
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .sketch(primitives: [
            .spline(
                entityID: SketchEntityID(),
                points: [],
                controlPoints: [],
                sketchPlane: .xy
            ),
        ])
    )
    let snapshot = ViewportSpatialOverlaySemanticSnapshot(
        scene: ViewportScene(items: [item]),
        interaction: .init(
            selectedFeatureIDs: [],
            selectedSceneNodeIDs: [],
            hoveredFeatureIDs: [],
            hoveredSceneNodeIDs: [],
            selectedSketchEntities: [],
            previewSketchEntities: [],
            hoveredSketchEntity: nil,
            selectedSketchRegions: [],
            previewSketchRegions: [],
            hoveredSketchRegion: nil
        ),
        editedBodies: [:],
        world: .init(
            modelBounds: item.modelBounds
        ),
        measurement: nil,
        drawsLegacyBodies: true,
        drawsDragPreviewBodies: false
    )
    let builder = ViewportSpatialOverlayProducer.makeBuilder(
        from: snapshot,
        topologyRevision: 2
    )

    do {
        _ = try await Task.detached {
            try builder(Point3D.origin, 0)
        }.value
        Issue.record("Malformed sketch source was published as a native batch.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .invalidSceneItem)
    } catch {
        Issue.record("Unexpected semantic snapshot failure: \(error)")
    }
}
