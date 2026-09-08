import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test
func rawSketchWorkerBuildsDimensionAndHandleDescriptorsFromScene() throws {
    let featureID = FeatureID()
    let entityID = SketchEntityID()
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "sketch",
            featureID: featureID,
            modelBounds: CGRect(x: 0, y: 0, width: 2, height: 2),
            kind: .sketch(primitives: [
                .line(
                    entityID: entityID,
                    start: CGPoint(x: 1, y: 2),
                    end: CGPoint(x: 3, y: 2)
                ),
            ])
        ),
    ])
    let selection = SelectionModel(selectedTargets: [
        SelectionTarget(
            sceneNodeID: SceneNodeID(),
            component: .sketchEntity(
                .sketchEntity(featureID: featureID, entityID: entityID)
            )
        ),
    ])
    let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
        document: .empty(),
        scene: scene,
        selection: selection,
        ruler: .standard(for: .meter),
        enabledRoutes: [.curvePointControl, .lineDimension]
    )

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    var visits = 0

    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        interactionRecords: &interactionRecords,
        activeFamilies: &families,
        checkpoint: { _, _, visitCount in visits += visitCount }
    )

    let handles = interactionRecords.map(\.identity)
    #expect(visits > 0)
    #expect(meshes.count == 1)
    #expect(cameraLines.count == 1)
    #expect(labels.count == 2)
    #expect(markers.count == 2)
    #expect(families == [.sketch, .curve])
    #expect(markers.map(\.value.anchor).contains(Point3D(x: 1, y: 0, z: 2)))
    #expect(markers.map(\.value.anchor).contains(Point3D(x: 3, y: 0, z: 2)))
    #expect(markers.allSatisfy { $0.value.hitTolerancePoints == 12.0 })

    let lineDimensionIndices = handles.enumerated().compactMap { index, identity in
        if case .sketchDimension = identity { return UInt32(index) }
        return nil
    }
    #expect(lineDimensionIndices.count == 2)
    #expect(cameraLines.allSatisfy { $0.value.handleIndex == nil })
    #expect(labels.allSatisfy { label in
        label.value.handleIndex.map { lineDimensionIndices.contains($0) } ?? false
    })
    #expect(labels.allSatisfy { label in label.value.hitRectPoints != nil })
    #expect(cameraLines.allSatisfy { $0.value.hitTolerancePoints == nil })
}

@Test
func rawSketchDimensionPairsSplitNativeLabelsAndHitRects() throws {
    let featureID = FeatureID()
    let lineID = SketchEntityID()
    let arcID = SketchEntityID()
    let nodeID = SceneNodeID()
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "dimension-pairs",
            featureID: featureID,
            sceneNodeID: nodeID,
            modelBounds: CGRect(x: -1, y: -1, width: 5, height: 4),
            kind: .sketch(primitives: [
                .line(entityID: lineID, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 2, y: 0)),
                .arc(
                    entityID: arcID,
                    center: CGPoint(x: 3, y: 0),
                    radiusMeters: 1,
                    startAngleRadians: 0,
                    endAngleRadians: .pi / 2.0
                ),
            ])
        ),
    ])
    let selection = SelectionModel(selectedTargets: [
        SelectionTarget(
            sceneNodeID: nodeID,
            component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: lineID))
        ),
        SelectionTarget(
            sceneNodeID: nodeID,
            component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: arcID))
        ),
    ])
    let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
        document: .empty(),
        scene: scene,
        selection: selection,
        ruler: .standard(for: .meter),
        enabledRoutes: [.lineDimension, .arcDimension]
    )

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []

    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        interactionRecords: &interactionRecords,
        activeFamilies: &families,
        checkpoint: { _, _, _ in }
    )

    func label(
        featureID: FeatureID,
        entityID: SketchEntityID,
        kind: SketchEntityDimensionKind
    ) -> RealityViewportSpatialBatch.Label? {
        let identity = ViewportSpatialHandleIdentity.sketchDimension(.init(
            featureID: featureID,
            entityID: entityID,
            kind: kind
        ))
        guard let recordIndex = interactionRecords.firstIndex(where: { $0.identity == identity }) else {
            return nil
        }
        return labels.first(where: { $0.value.handleIndex == UInt32(recordIndex) })?.value
    }

    func assertPair(
        left: RealityViewportSpatialBatch.Label,
        right: RealityViewportSpatialBatch.Label,
        combinedText: String
    ) throws {
        guard case .trailing = left.alignment else {
            Issue.record("The left dimension label must use native trailing alignment.")
            return
        }
        guard case .leading = right.alignment else {
            Issue.record("The right dimension label must use native leading alignment.")
            return
        }
        #expect(left.anchor == right.anchor)
        let leftRect = try #require(left.hitRectPoints)
        let rightRect = try #require(right.hitRectPoints)
        let width = max(52.0, CGFloat(combinedText.count) * 6.4 + 16.0)
        let halfWidth = width * 0.5
        let expectedHeight: CGFloat = 30.0
        #expect(abs(leftRect.minX - (-(halfWidth + 4.0))) < 0.0001)
        #expect(abs(leftRect.maxX - 4.0) < 0.0001)
        #expect(abs(rightRect.minX + 4.0) < 0.0001)
        #expect(abs(rightRect.maxX - (halfWidth + 4.0)) < 0.0001)
        #expect(abs(leftRect.height - expectedHeight) < 0.0001)
        #expect(abs(rightRect.height - expectedHeight) < 0.0001)
        #expect(leftRect.midX < rightRect.midX)
        #expect(abs(leftRect.midX - rightRect.midX) > 0.0001)
    }

    let lineLength = try #require(label(featureID: featureID, entityID: lineID, kind: .length))
    let lineAngle = try #require(label(featureID: featureID, entityID: lineID, kind: .angle))
    let arcRadius = try #require(label(featureID: featureID, entityID: arcID, kind: .radius))
    let arcAngle = try #require(label(featureID: featureID, entityID: arcID, kind: .angle))
    try assertPair(
        left: lineLength,
        right: lineAngle,
        combinedText: "L \(lineLength.text) / A \(lineAngle.text)"
    )
    try assertPair(
        left: arcRadius,
        right: arcAngle,
        combinedText: "R \(arcRadius.text) / A \(arcAngle.text)"
    )
}

@Test
func rawSketchWorkerAppliesUncommittedPointOverrideInWorldXzSpace() throws {
    let featureID = FeatureID()
    let entityID = SketchEntityID()
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "sketch",
            featureID: featureID,
            modelBounds: CGRect(x: 0, y: 0, width: 2, height: 2),
            kind: .sketch(primitives: [
                .line(
                    entityID: entityID,
                    start: CGPoint(x: 1, y: 2),
                    end: CGPoint(x: 3, y: 2)
                ),
            ])
        ),
    ])
    let selection = SelectionModel(selectedTargets: [
        SelectionTarget(
            sceneNodeID: SceneNodeID(),
            component: .sketchEntity(
                .sketchEntity(featureID: featureID, entityID: entityID)
            )
        ),
    ])
    let identity = ViewportSpatialHandleIdentity.sketchPointHandle(.init(
        featureID: featureID,
        entityID: entityID,
        handle: .lineStart
    ))
    let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
        document: .empty(),
        scene: scene,
        selection: selection,
        ruler: .standard(for: .meter),
        enabledRoutes: [.curvePointControl],
        activeOverrides: [
            .init(identity: identity, deltaX: 1.5, deltaY: 0.25),
        ]
    )

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []

    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        interactionRecords: &interactionRecords,
        activeFamilies: &families,
        checkpoint: { _, _, _ in }
    )

    let handles = interactionRecords.map(\.identity)
    #expect(markers.count == 2)
    #expect(markers.map(\.value.anchor).contains(Point3D(x: 2.5, y: 0.0, z: 2.25)))
    #expect(markers.map(\.value.anchor).contains(Point3D(x: 3.0, y: 0.0, z: 2.0)))
    #expect(markers.first(where: { $0.value.handleIndex != nil })?.value.handleIndex
        == handles.firstIndex(of: identity).map(UInt32.init))
}

@Test
func preparedSketchTargetsRetainTheSourcePlane() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Source plane", plane: .yz,
        start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
        end: SketchPoint(x: .length(0.02, .meter), y: .length(0.01, .meter))
    )
    let scene = ViewportSceneBuilder().build(document: document, ruler: .standard(for: .meter))
    let item = try #require(scene.items.first { $0.featureID == featureID })
    guard case .sketch(let primitives) = item.kind else {
        Issue.record("The fixture must produce a sketch.")
        return
    }
    let entityID = try #require(primitives.first?.entityID)
    let selection = SelectionModel(selectedTargets: [SelectionTarget(
        sceneNodeID: try #require(item.sceneNodeID),
        component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID))
    )])
    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var lines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var records: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: .init(document: document, scene: scene, selection: selection,
                    ruler: .standard(for: .meter), enabledRoutes: [.curvePointControl, .lineDimension]),
        meshes: &meshes, paths: &paths, labels: &labels, markers: &markers,
        cameraLines: &lines, cameraPaths: &cameraPaths, interactionRecords: &records,
        activeFamilies: &families, checkpoint: { _, _, _ in }
    )
    #expect(!records.isEmpty)
    for record in records {
        switch record.target {
        case .sketchPointHandle(let target): #expect(target.sketchPlane == .yz)
        case .sketchDimension(let target): #expect(target.sketchPlane == .yz)
        default: Issue.record("Unexpected sketch interaction route.")
        }
    }
}

@Test
func rawBridgeWorkerResolvesActiveParameterFromDocumentAndScene() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Bridge Worker",
        plane: .xy,
        start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
        end: SketchPoint(x: .length(0.003, .meter), y: .length(0.0, .meter))
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        Issue.record("Bridge worker fixture requires a source sketch line.")
        return
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: SketchPoint(x: .length(0.006, .meter), y: .length(0.003, .meter)),
            end: SketchPoint(x: .length(0.006, .meter), y: .length(0.006, .meter))
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()

    let bridgeID = try document.createBridgeCurve(
        featureID: featureID,
        firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(firstLineID)),
        secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(secondLineID)),
        continuity: .g1
    )
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
    let summary = try SketchEntitySnapshotService().snapshot(document: document)
    let bridgeEntry = try #require(summary.entries.first { $0.entityID == bridgeID.description })
    let selectionTarget = try #require(bridgeEntry.selectionTarget())
    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .meter)
    )
    let identity = ViewportSpatialHandleIdentity.bridgeCurveEndpoint(.init(
        sourceID: source.id,
        role: .first
    ))
    let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
        document: document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [selectionTarget]),
        ruler: .standard(for: .meter),
        enabledRoutes: [.bridgeCurveEndpoint],
        activeOverrides: [
            .init(
                identity: identity,
                bridgeEndpoint: source.firstEndpoint,
                bridgeParameter: 0.5
            ),
        ]
    )

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []

    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        interactionRecords: &interactionRecords,
        activeFamilies: &families,
        checkpoint: { _, _, _ in }
    )

    #expect(families == [.curve])
    #expect(meshes.count == 2)
    #expect(cameraLines.count == 2)
    #expect(markers.count == 2)
    #expect(markers.contains {
        abs($0.value.anchor.x - 0.0015) < 1.0e-9
            && abs($0.value.anchor.y) < 1.0e-9
            && abs($0.value.anchor.z) < 1.0e-9
    })
}

@Test
func rawWorkerUsesViewportGuideDefaultsAndActiveOverrides() throws {
    let featureID = FeatureID()
    let lineEntityID = SketchEntityID()
    let lineNodeID = SceneNodeID()
    let bodyNodeID = SceneNodeID()
    let edge = ViewportBodyEdge.leftBottom
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "guide-sketch",
            featureID: featureID,
            sceneNodeID: lineNodeID,
            modelBounds: CGRect(x: 0, y: 0, width: 2, height: 2),
            kind: .sketch(primitives: [
                .line(
                    entityID: lineEntityID,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 2, y: 0)
                ),
            ])
        ),
        ViewportSceneItem(
            id: "guide-body",
            featureID: FeatureID(),
            sceneNodeID: bodyNodeID,
            modelBounds: CGRect(x: 0, y: 0, width: 2, height: 2),
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: 2,
                sizeYMeters: 1,
                sizeZMeters: 2,
                yMinMeters: 0,
                yMaxMeters: 1
            ))
        ),
    ])
    let bodyFeatureID = scene.items[1].featureID
    let lineSelection = SelectionTarget(
        sceneNodeID: lineNodeID,
        component: .sketchEntity(.sketchEntity(
            featureID: featureID,
            entityID: lineEntityID
        ))
    )
    let edgeSelection = SelectionTarget(
        sceneNodeID: bodyNodeID,
        component: .edge(.bodyEdgeLeftBottom)
    )
    let selection = SelectionModel(selectedTargets: [lineSelection, edgeSelection])
    let slotIdentity = ViewportSpatialHandleIdentity.slotWidth(.init(
        featureID: featureID,
        entityID: lineEntityID
    ))
    let sketchStartIdentity = ViewportSpatialHandleIdentity.sketchVertexOffset(.init(
        featureID: featureID,
        entityID: lineEntityID,
        handle: .lineStart
    ))
    let sketchEndIdentity = ViewportSpatialHandleIdentity.sketchVertexOffset(.init(
        featureID: featureID,
        entityID: lineEntityID,
        handle: .lineEnd
    ))
    let edgeIdentity = ViewportSpatialHandleIdentity.edgeOffset(.init(
        featureID: bodyFeatureID,
        edge: edge
    ))
    let customSlotWidth = 0.024
    let customSketchDistance = 0.011
    let customEdgeDistance = 0.017

    func append(
        activeOverrides: [ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.ActiveOverride] = []
    ) throws -> (
        meshes: [ViewportSpatialOverlayInput.Mesh],
        markers: [ViewportSpatialOverlayInput.Marker],
        cameraLines: [ViewportSpatialOverlayInput.CameraLine],
        cameraPaths: [ViewportSpatialOverlayInput.CameraPath],
        handles: [ViewportSpatialHandleIdentity]
    ) {
        let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
            document: .empty(),
            scene: scene,
            selection: selection,
            ruler: .standard(for: .meter),
            enabledRoutes: [.slotWidth, .sketchVertexOffset, .edgeOffset],
            activeOverrides: activeOverrides,
            slotWidthMeters: customSlotWidth,
            sketchVertexOffsetDistanceMeters: customSketchDistance,
            edgeOffsetDistanceMeters: customEdgeDistance
        )
        var meshes: [ViewportSpatialOverlayInput.Mesh] = []
        var paths: [ViewportSpatialOverlayInput.Path] = []
        var labels: [ViewportSpatialOverlayInput.Label] = []
        var markers: [ViewportSpatialOverlayInput.Marker] = []
        var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
        var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
        var interactionRecords: [ViewportSpatialInteractionRecord] = []
        var families: Set<ViewportSpatialOverlayFamily> = []
        try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
            from: input,
            meshes: &meshes,
            paths: &paths,
            labels: &labels,
            markers: &markers,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            interactionRecords: &interactionRecords,
            activeFamilies: &families,
            checkpoint: { _, _, _ in }
        )
        return (meshes, markers, cameraLines, cameraPaths, interactionRecords.map(\.identity))
    }

    func length(_ start: Point3D, _ end: Point3D) -> Double {
        hypot(hypot(end.x - start.x, end.y - start.y), end.z - start.z)
    }

    let defaults = try append()
    let edgeIndex = UInt32(try #require(defaults.handles.firstIndex(of: edgeIdentity)))
    let slotMesh = try #require(defaults.meshes.first {
        abs(length($0.value.positions[0], $0.value.positions[1]) - customSlotWidth * 0.5) < 1.0e-12
    }).value
    let sketchMeshes = defaults.meshes.filter {
        abs(length($0.value.positions[0], $0.value.positions[1]) - customSketchDistance) < 1.0e-12
    }
    let edgeTip = try #require(defaults.cameraPaths.first { $0.value.handleIndex == edgeIndex }).value
    #expect(abs(length(slotMesh.positions[0], slotMesh.positions[1]) - customSlotWidth * 0.5) < 1.0e-12)
    #expect(sketchMeshes.count == 2)
    #expect(sketchMeshes.allSatisfy {
        abs(length($0.value.positions[0], $0.value.positions[1]) - customSketchDistance) < 1.0e-12
    })
    #expect(defaults.cameraLines.count == 4)
    #expect(defaults.cameraLines.allSatisfy { $0.value.hitTolerancePoints == 10.0 })
    #expect(defaults.markers.isEmpty)
    #expect(defaults.cameraPaths.count == 4)
    #expect(defaults.cameraPaths.allSatisfy { $0.value.hitTolerancePoints == 14.0 })
    #expect(defaults.cameraPaths.allSatisfy {
        if case .projected(_, let minimumLength, _, _) = $0.value.offset {
            return abs(minimumLength - 64.0) < 1.0e-12
        }
        return false
    })
    let edgeMidpoint = Point3D(x: 0.0, y: 0.5, z: 0.0)
    #expect(abs(edgeTip.anchor.x - edgeMidpoint.x) < 1.0e-12)

    let slotOverride = 0.042
    let sketchOverride = 0.035
    let edgeOverride = 0.029
    let overrides = try append(activeOverrides: [
        .init(identity: slotIdentity, widthMeters: slotOverride),
        .init(identity: sketchStartIdentity, distanceMeters: sketchOverride),
        .init(identity: edgeIdentity, distanceMeters: edgeOverride),
    ])
    let overrideEdgeIndex = UInt32(try #require(overrides.handles.firstIndex(of: edgeIdentity)))
    let overrideSlotMesh = try #require(overrides.meshes.first {
        abs(length($0.value.positions[0], $0.value.positions[1]) - slotOverride * 0.5) < 1.0e-12
    }).value
    let overrideSketchMeshes = overrides.meshes.filter {
        abs(length($0.value.positions[0], $0.value.positions[1]) - customSketchDistance) < 1.0e-12
            || abs(length($0.value.positions[0], $0.value.positions[1]) - sketchOverride) < 1.0e-12
    }
    let overrideEdgeTip = try #require(overrides.cameraPaths.first { $0.value.handleIndex == overrideEdgeIndex }).value
    #expect(abs(length(overrideSlotMesh.positions[0], overrideSlotMesh.positions[1]) - slotOverride * 0.5) < 1.0e-12)
    #expect(overrideSketchMeshes.count == 2)
    #expect(overrideSketchMeshes.contains {
        abs(length($0.value.positions[0], $0.value.positions[1]) - sketchOverride) < 1.0e-12
    })
    #expect(overrideSketchMeshes.contains {
        abs(length($0.value.positions[0], $0.value.positions[1]) - customSketchDistance) < 1.0e-12
    })
    #expect(abs(overrideEdgeTip.anchor.x - edgeMidpoint.x) < 1.0e-12)
}

@Test
func preparedOffsetTargetsRetainSourceBaselineWhenVisualPointIsDragged() throws {
    let featureID = FeatureID()
    let entityID = SketchEntityID()
    let nodeID = SceneNodeID()
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "baseline-sketch",
            featureID: featureID,
            sceneNodeID: nodeID,
            modelBounds: CGRect(x: 0, y: 0, width: 2, height: 1),
            kind: .sketch(primitives: [
                .line(
                    entityID: entityID,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 2, y: 0)
                ),
            ])
        ),
    ])
    let selectionTarget = SelectionTarget(
        sceneNodeID: nodeID,
        component: .sketchEntity(.sketchEntity(
            featureID: featureID,
            entityID: entityID
        ))
    )
    let pointIdentity = ViewportSpatialHandleIdentity.sketchPointHandle(.init(
        featureID: featureID,
        entityID: entityID,
        handle: .lineStart
    ))
    let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
        document: .empty(),
        scene: scene,
        selection: SelectionModel(selectedTargets: [selectionTarget]),
        ruler: .standard(for: .meter),
        enabledRoutes: [.slotWidth, .sketchVertexOffset],
        activeOverrides: [
            .init(identity: pointIdentity, deltaX: 1.0, deltaY: 0.0),
        ],
        slotWidthMeters: 0.024,
        sketchVertexOffsetDistanceMeters: 0.011
    )

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        interactionRecords: &interactionRecords,
        activeFamilies: &families,
        checkpoint: { _, _, _ in }
    )

    let slotRecord = try #require(interactionRecords.first { record in
        if case .slotWidth = record.target { return true }
        return false
    })
    if case .slotWidth(_, _, _, let axis) = slotRecord.target {
        #expect(abs(axis.origin.x - 1.0) < 1.0e-12)
        #expect(abs(axis.origin.z) < 1.0e-12)
        #expect(abs(axis.direction.x) < 1.0e-12)
        #expect(abs(axis.direction.y) < 1.0e-12)
        #expect(abs(axis.direction.z - 1.0) < 1.0e-12)
    } else {
        Issue.record("Slot width record used an unexpected prepared target.")
    }

    let vertexRecord = try #require(interactionRecords.first { record in
        if case .sketchVertexOffset = record.target { return true }
        return false
    })
    if case .sketchVertexOffset(_, _, _, _, let axis) = vertexRecord.target {
        #expect(abs(axis.origin.x) < 1.0e-12)
        #expect(abs(axis.origin.y) < 1.0e-12)
        #expect(abs(axis.origin.z) < 1.0e-12)
    } else {
        Issue.record("Sketch vertex record used an unexpected prepared target.")
    }
    let vertexIndex = try ViewportSpatialOverlayProducer.handleIndex(
        for: vertexRecord.identity, occurrenceID: vertexRecord.occurrenceID, in: interactionRecords)
    let vertexTip = try #require(cameraPaths.first { $0.value.handleIndex == vertexIndex })
    #expect(abs(vertexTip.value.anchor.x - 1.0) < 1.0e-12)
}

@Test
func rawWorkerCoversCircleArcSplineAndOffsetRoutes() throws {
    let featureID = FeatureID()
    let circleID = SketchEntityID()
    let arcID = SketchEntityID()
    let splineID = SketchEntityID()
    let nodeID = SceneNodeID()
    let regionID = SelectionComponentID.profileRegion(featureID: featureID, profileIndex: 0)
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "route-matrix",
            featureID: featureID,
            sceneNodeID: nodeID,
            modelBounds: CGRect(x: -1, y: -1, width: 3, height: 3),
            kind: .sketch(primitives: [
                .circle(entityID: circleID, center: CGPoint(x: 0, y: 0), radiusMeters: 0.5),
                .arc(
                    entityID: arcID,
                    center: CGPoint(x: 1, y: 0),
                    radiusMeters: 0.5,
                    startAngleRadians: 0,
                    endAngleRadians: .pi * 0.75
                ),
                .spline(
                    entityID: splineID,
                    points: [
                        CGPoint(x: 0, y: 1),
                        CGPoint(x: 0.5, y: 1.25),
                        CGPoint(x: 1, y: 1),
                    ],
                    controlPoints: [
                        CGPoint(x: 0, y: 1),
                        CGPoint(x: 0.5, y: 1.5),
                        CGPoint(x: 1, y: 1),
                    ],
                    sketchPlane: .defaultWorkspacePlane
                ),
            ]),
            sketchRegions: [
                ViewportSketchRegion(
                    componentID: regionID,
                    points: [
                        CGPoint(x: -0.5, y: -0.5),
                        CGPoint(x: 0.5, y: -0.5),
                        CGPoint(x: 0.5, y: 0.5),
                        CGPoint(x: -0.5, y: 0.5),
                    ]
                ),
            ]
        ),
    ])
    let selection = SelectionModel(selectedTargets: [
        SelectionTarget(
            sceneNodeID: nodeID,
            component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: circleID))
        ),
        SelectionTarget(
            sceneNodeID: nodeID,
            component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: arcID))
        ),
        SelectionTarget(
            sceneNodeID: nodeID,
            component: .sketchEntity(.sketchControlPoint(featureID: featureID, entityID: splineID, index: 1))
        ),
        SelectionTarget(sceneNodeID: nodeID, component: .region(regionID)),
    ])
    let input = ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.RawInput(
        document: .empty(),
        scene: scene,
        selection: selection,
        ruler: .standard(for: .meter),
        enabledRoutes: [
            .curvePointControl,
            .circleDimension,
            .arcDimension,
            .splineControl,
            .splineSlide,
            .regionOffset,
            .slotWidth,
            .sketchVertexOffset,
        ]
    )
    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        interactionRecords: &interactionRecords,
        activeFamilies: &families,
        checkpoint: { _, _, _ in }
    )

    let handles = interactionRecords.map(\.identity)
    #expect(families == [.sketch, .curve])
    #expect(handles.contains { if case .sketchDimension(let value) = $0 { return value.entityID == circleID && value.kind == .radius }; return false })
    #expect(handles.contains { if case .sketchDimension(let value) = $0 { return value.entityID == arcID && value.kind == .radius }; return false })
    #expect(handles.contains { if case .sketchDimension(let value) = $0 { return value.entityID == arcID && value.kind == .angle }; return false })
    #expect(handles.contains { if case .splineControlPoint(let value) = $0 { return value.entityID == splineID && value.controlPointIndex == 1 }; return false })
    #expect(handles.contains { if case .splineControlPointSlide(let value) = $0 { return value.entityID == splineID && value.controlPointIndexes == [1] }; return false })
    #expect(handles.contains { if case .regionOffset(let value) = $0 { return value.componentID == regionID }; return false })
    #expect(handles.contains { if case .slotWidth(let value) = $0 { return value.entityID == arcID }; return false })
    #expect(handles.contains { if case .sketchVertexOffset(let value) = $0 { return value.entityID == arcID && value.handle == .arcStart }; return false })
    #expect(meshes.isEmpty == false)
    #expect(markers.isEmpty == false)
    #expect(cameraLines.isEmpty == false)
}

@Test
func offsetRoutesKeepTipFootprintWithProjectedGuideEndpoint() throws {
    let featureID = FeatureID()
    let componentID = SelectionComponentID.profileRegion(featureID: featureID, profileIndex: 0)
    let edge = try ViewportSpatialOverlayProducer.makeEdgeOffsetEntry(
        featureID: featureID,
        edge: .leftBottom,
        edgeStart: Point3D(x: -1.0, y: 0.0, z: 0.0),
        edgeEnd: Point3D(x: 1.0, y: 0.0, z: 0.0),
        inwardToward: Point3D(x: 0.0, y: 1.0, z: 0.0),
        distanceMeters: 0.2,
        selectionTarget: nil,
        baseValue: 0.2,
        label: "edge",
        state: .normal
    )
    let region = try ViewportSpatialOverlayProducer.makeRegionOffsetEntry(
        featureID: featureID,
        componentID: componentID,
        sourceVertices: [
            Point3D(x: -1.0, y: -1.0, z: 0.0),
            Point3D(x: 1.0, y: -1.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ],
        distanceMeters: 0.2,
        selectionTarget: nil,
        baseValue: 0.2,
        label: "region",
        state: .normal
    )
    let slot = try ViewportSpatialOverlayProducer.makeSlotWidthEntry(
        featureID: featureID,
        entityID: SketchEntityID(),
        base: Point3D.origin,
        direction: Vector3D(x: 0.0, y: 1.0, z: 0.0),
        widthMeters: 0.2,
        baseValue: 0.2,
        selectionTarget: nil,
        label: "slot",
        state: .normal
    )
    let vertex = try ViewportSpatialOverlayProducer.makeSketchVertexOffsetEntry(
        featureID: featureID,
        entityID: SketchEntityID(),
        handle: .point,
        base: Point3D.origin,
        direction: Vector3D(x: 1.0, y: 0.0, z: 0.0),
        distanceMeters: 0.2,
        baseValue: 0.2,
        selectionTarget: nil,
        label: "vertex",
        state: .normal
    )
    let spline = try ViewportSpatialOverlayProducer.makeSplineSlideEntries(
        featureID: featureID,
        entityID: SketchEntityID(),
        controlPoints: [
            Point3D(x: -1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
        ],
        selectedIndexes: [1],
        direction: .positiveU,
        distanceMeters: 0.2,
        selectionTarget: nil,
        baseValue: 0.2,
        label: "spline",
        state: .normal
    )

    func assertTip(
        _ entry: ViewportSpatialOverlayProducer.SketchCurveAffordanceSource.Entry,
        minimumLength: Double?,
        parallel: Double,
        anchor: Point3D,
        toward: Point3D
    ) throws {
        let guide = try #require(entry.cameraGuides.first)
        let guideTip = try #require(guide.points.last)
        let footprint = try #require(entry.cameraPaths.first?.placement)
        #expect(guide.points.first?.minimumLength == nil)
        if let minimumLength {
            #expect(abs((guideTip.minimumLength ?? .nan) - minimumLength) < 1.0e-12)
            #expect(abs((footprint.minimumLength ?? .nan) - minimumLength) < 1.0e-12)
        } else {
            #expect(guideTip.minimumLength == nil)
            #expect(footprint.minimumLength == nil)
        }
        #expect(abs(guideTip.parallel - parallel) < 1.0e-12)
        #expect(abs(footprint.parallel - parallel) < 1.0e-12)
        #expect(abs(guideTip.anchor.x - anchor.x) < 1.0e-12)
        #expect(abs(guideTip.anchor.y - anchor.y) < 1.0e-12)
        #expect(abs(guideTip.anchor.z - anchor.z) < 1.0e-12)
        #expect(abs(footprint.anchor.x - anchor.x) < 1.0e-12)
        #expect(abs(footprint.anchor.y - anchor.y) < 1.0e-12)
        #expect(abs(footprint.anchor.z - anchor.z) < 1.0e-12)
        #expect(abs(guideTip.toward.x - toward.x) < 1.0e-12)
        #expect(abs(guideTip.toward.y - toward.y) < 1.0e-12)
        #expect(abs(guideTip.toward.z - toward.z) < 1.0e-12)
        #expect(abs(footprint.toward.x - toward.x) < 1.0e-12)
        #expect(abs(footprint.toward.y - toward.y) < 1.0e-12)
        #expect(abs(footprint.toward.z - toward.z) < 1.0e-12)
        #expect(entry.markers.isEmpty)
    }

    try assertTip(
        region,
        minimumLength: nil,
        parallel: 64.0,
        anchor: Point3D(x: 0.0, y: 1.2, z: 0.0),
        toward: Point3D(x: 0.0, y: 2.2, z: 0.0)
    )
    let negativeRegion = try ViewportSpatialOverlayProducer.makeRegionOffsetEntry(
        featureID: featureID,
        componentID: componentID,
        sourceVertices: [
            Point3D(x: -1.0, y: -1.0, z: 0.0),
            Point3D(x: 1.0, y: -1.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ],
        distanceMeters: -0.2,
        selectionTarget: nil,
        baseValue: -0.2,
        label: nil,
        state: .normal
    )
    try assertTip(
        negativeRegion,
        minimumLength: nil,
        parallel: 64.0,
        anchor: Point3D(x: 0.0, y: 0.8, z: 0.0),
        toward: Point3D(x: 0.0, y: 1.8, z: 0.0)
    )
    try assertTip(
        edge,
        minimumLength: 64.0,
        parallel: 0.0,
        anchor: Point3D(x: 0.0, y: 0.0, z: 0.0),
        toward: Point3D(x: 0.0, y: 0.2, z: 0.0)
    )
    try assertTip(
        slot,
        minimumLength: 64.0,
        parallel: 0.0,
        anchor: .origin,
        toward: Point3D(x: 0.0, y: 0.1, z: 0.0)
    )
    try assertTip(
        vertex,
        minimumLength: 64.0,
        parallel: 0.0,
        anchor: .origin,
        toward: Point3D(x: 0.2, y: 0.0, z: 0.0)
    )
    try assertTip(
        spline,
        minimumLength: 0.0,
        parallel: 0.0,
        anchor: .origin,
        toward: Point3D(x: 0.2, y: 0.0, z: 0.0)
    )

    let zeroSpline = try ViewportSpatialOverlayProducer.makeSplineSlideEntries(
        featureID: featureID,
        entityID: SketchEntityID(),
        controlPoints: [
            Point3D(x: -1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
        ],
        selectedIndexes: [1],
        direction: .positiveU,
        distanceMeters: 0.0,
        selectionTarget: nil,
        baseValue: 0.0,
        label: "zero spline",
        state: .normal
    )
    try assertTip(
        zeroSpline,
        minimumLength: nil,
        parallel: 62.0,
        anchor: .origin,
        toward: Point3D(x: 1.0, y: 0.0, z: 0.0)
    )

    let negativeSpline = try ViewportSpatialOverlayProducer.makeSplineSlideEntries(
        featureID: featureID,
        entityID: SketchEntityID(),
        controlPoints: [
            Point3D(x: -1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
        ],
        selectedIndexes: [1],
        direction: .positiveU,
        distanceMeters: -0.2,
        selectionTarget: nil,
        baseValue: 0.0,
        label: "negative spline",
        state: .normal
    )
    try assertTip(
        negativeSpline,
        minimumLength: 0.0,
        parallel: 0.0,
        anchor: .origin,
        toward: Point3D(x: -0.2, y: 0.0, z: 0.0)
    )

    let smallSpline = try ViewportSpatialOverlayProducer.makeSplineSlideEntries(
        featureID: featureID,
        entityID: SketchEntityID(),
        controlPoints: [
            Point3D(x: -1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
        ],
        selectedIndexes: [1],
        direction: .positiveU,
        distanceMeters: 1.0e-6,
        selectionTarget: nil,
        baseValue: 0.0,
        label: "small spline",
        state: .normal
    )
    try assertTip(
        smallSpline,
        minimumLength: 0.0,
        parallel: 0.0,
        anchor: .origin,
        toward: Point3D(x: 1.0e-6, y: 0.0, z: 0.0)
    )

    let zeroEdge = try ViewportSpatialOverlayProducer.makeEdgeOffsetEntry(
        featureID: featureID,
        edge: .leftBottom,
        edgeStart: Point3D(x: -1.0, y: 0.0, z: 0.0),
        edgeEnd: Point3D(x: 1.0, y: 0.0, z: 0.0),
        inwardToward: Point3D(x: 0.0, y: 1.0, z: 0.0),
        distanceMeters: 0.0,
        selectionTarget: nil,
        baseValue: 0.0,
        label: nil,
        state: .normal
    )
    try assertTip(
        zeroEdge,
        minimumLength: nil,
        parallel: 64.0,
        anchor: .origin,
        toward: Point3D(x: 0.0, y: 1.0, z: 0.0)
    )

    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportSpatialOverlayProducer.makeSlotWidthEntry(
            featureID: featureID, entityID: SketchEntityID(), base: .origin,
            direction: Vector3D(x: 0.0, y: 1.0, z: 0.0), widthMeters: 0.0,
            baseValue: 0.0, selectionTarget: nil, label: nil, state: .normal)
    }

    let zeroVertex = try ViewportSpatialOverlayProducer.makeSketchVertexOffsetEntry(
        featureID: featureID,
        entityID: SketchEntityID(),
        handle: .point,
        base: .origin,
        direction: Vector3D(x: 1.0, y: 0.0, z: 0.0),
        distanceMeters: 0.0,
        baseValue: 0.0,
        selectionTarget: nil,
        label: nil,
        state: .normal
    )
    try assertTip(
        zeroVertex,
        minimumLength: nil,
        parallel: 64.0,
        anchor: .origin,
        toward: Point3D(x: 1.0, y: 0.0, z: 0.0)
    )
}
