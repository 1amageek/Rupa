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
    var handles: [ViewportSpatialHandleIdentity] = []
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
        handleIdentities: &handles,
        activeFamilies: &families,
        checkpoint: { _, _, visitCount in visits += visitCount }
    )

    #expect(visits > 0)
    #expect(meshes.count == 1)
    #expect(cameraLines.count == 1)
    #expect(labels.count == 2)
    #expect(markers.count == 2)
    #expect(families == [.sketch, .curve])
    #expect(markers.map(\.value.anchor).contains(Point3D(x: 1, y: 0, z: 2)))
    #expect(markers.map(\.value.anchor).contains(Point3D(x: 3, y: 0, z: 2)))

    let lineDimensionIndices = handles.enumerated().compactMap { index, identity in
        if case .sketchDimension = identity { return UInt32(index) }
        return nil
    }
    #expect(lineDimensionIndices.count == 2)
    let cameraGuideHandle = try #require(cameraLines.first?.value.handleIndex)
    #expect(lineDimensionIndices.contains(cameraGuideHandle))
    #expect(cameraGuideHandle < UInt32(handles.count))
    #expect(handles[Int(cameraGuideHandle)] == .sketchDimension(.init(
        featureID: featureID,
        entityID: entityID,
        kind: .length
    )))
    #expect(labels.allSatisfy { label in
        label.value.handleIndex.map { lineDimensionIndices.contains($0) } ?? false
    })
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
    var handles: [ViewportSpatialHandleIdentity] = []
    var families: Set<ViewportSpatialOverlayFamily> = []

    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        handleIdentities: &handles,
        activeFamilies: &families,
        checkpoint: { _, _, _ in }
    )

    #expect(markers.count == 2)
    #expect(markers.map(\.value.anchor).contains(Point3D(x: 2.5, y: 0.0, z: 2.25)))
    #expect(markers.map(\.value.anchor).contains(Point3D(x: 3.0, y: 0.0, z: 2.0)))
    #expect(markers.first(where: { $0.value.handleIndex != nil })?.value.handleIndex
        == handles.firstIndex(of: identity).map(UInt32.init))
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
    var handles: [ViewportSpatialHandleIdentity] = []
    var families: Set<ViewportSpatialOverlayFamily> = []

    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        handleIdentities: &handles,
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
        var handles: [ViewportSpatialHandleIdentity] = []
        var families: Set<ViewportSpatialOverlayFamily> = []
        try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
            from: input,
            meshes: &meshes,
            paths: &paths,
            labels: &labels,
            markers: &markers,
            cameraLines: &cameraLines,
            cameraPaths: &cameraPaths,
            handleIdentities: &handles,
            activeFamilies: &families,
            checkpoint: { _, _, _ in }
        )
        return (meshes, markers, handles)
    }

    func length(_ start: Point3D, _ end: Point3D) -> Double {
        hypot(hypot(end.x - start.x, end.y - start.y), end.z - start.z)
    }

    let defaults = try append()
    let slotIndex = UInt32(try #require(defaults.handles.firstIndex(of: slotIdentity)))
    let sketchStartIndex = UInt32(try #require(defaults.handles.firstIndex(of: sketchStartIdentity)))
    let sketchEndIndex = UInt32(try #require(defaults.handles.firstIndex(of: sketchEndIdentity)))
    let edgeIndex = UInt32(try #require(defaults.handles.firstIndex(of: edgeIdentity)))
    let slotMesh = try #require(defaults.meshes.first { $0.value.handleIndex == slotIndex }).value
    let sketchStartMesh = try #require(defaults.meshes.first { $0.value.handleIndex == sketchStartIndex }).value
    let sketchEndMesh = try #require(defaults.meshes.first { $0.value.handleIndex == sketchEndIndex }).value
    let edgeMarker = try #require(defaults.markers.first { $0.value.handleIndex == edgeIndex }).value
    #expect(abs(length(slotMesh.positions[0], slotMesh.positions[1]) - customSlotWidth * 0.5) < 1.0e-12)
    #expect(abs(length(sketchStartMesh.positions[0], sketchStartMesh.positions[1]) - customSketchDistance) < 1.0e-12)
    #expect(abs(length(sketchEndMesh.positions[0], sketchEndMesh.positions[1]) - customSketchDistance) < 1.0e-12)
    let edgeMidpoint = Point3D(x: 0.0, y: 0.5, z: 0.0)
    #expect(abs(length(edgeMidpoint, edgeMarker.anchor) - customEdgeDistance) < 1.0e-12)

    let slotOverride = 0.042
    let sketchOverride = 0.035
    let edgeOverride = 0.029
    let overrides = try append(activeOverrides: [
        .init(identity: slotIdentity, widthMeters: slotOverride),
        .init(identity: sketchStartIdentity, distanceMeters: sketchOverride),
        .init(identity: edgeIdentity, distanceMeters: edgeOverride),
    ])
    let overrideSlotIndex = UInt32(try #require(overrides.handles.firstIndex(of: slotIdentity)))
    let overrideSketchStartIndex = UInt32(try #require(overrides.handles.firstIndex(of: sketchStartIdentity)))
    let overrideSketchEndIndex = UInt32(try #require(overrides.handles.firstIndex(of: sketchEndIdentity)))
    let overrideEdgeIndex = UInt32(try #require(overrides.handles.firstIndex(of: edgeIdentity)))
    let overrideSlotMesh = try #require(overrides.meshes.first { $0.value.handleIndex == overrideSlotIndex }).value
    let overrideSketchStartMesh = try #require(overrides.meshes.first { $0.value.handleIndex == overrideSketchStartIndex }).value
    let overrideSketchEndMesh = try #require(overrides.meshes.first { $0.value.handleIndex == overrideSketchEndIndex }).value
    let overrideEdgeMarker = try #require(overrides.markers.first { $0.value.handleIndex == overrideEdgeIndex }).value
    #expect(abs(length(overrideSlotMesh.positions[0], overrideSlotMesh.positions[1]) - slotOverride * 0.5) < 1.0e-12)
    #expect(abs(length(overrideSketchStartMesh.positions[0], overrideSketchStartMesh.positions[1]) - sketchOverride) < 1.0e-12)
    #expect(abs(length(overrideSketchEndMesh.positions[0], overrideSketchEndMesh.positions[1]) - customSketchDistance) < 1.0e-12)
    #expect(abs(length(edgeMidpoint, overrideEdgeMarker.anchor) - edgeOverride) < 1.0e-12)
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
    var handles: [ViewportSpatialHandleIdentity] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSketchCurveAffordances(
        from: input,
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        handleIdentities: &handles,
        activeFamilies: &families,
        checkpoint: { _, _, _ in }
    )

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
