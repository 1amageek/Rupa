import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test
func rawSurfaceTransformInputBuildsBodyTransformFromDocumentSceneAndSelection() throws {
    let featureID = FeatureID()
    let nodeID = SceneNodeID()
    let edge = ViewportBodyTopology.Edge(
        componentID: .bodyEdgeLeftBottom,
        start: Point3D(x: -1, y: 0, z: -1),
        end: Point3D(x: 1, y: 0, z: -1)
    )
    let topology = ViewportBodyTopology(
        faces: [],
        edges: [edge],
        vertices: [
            .init(componentID: SelectionComponentID(rawValue: "body.vertex.0"), point: .origin),
        ]
    )
    let item = ViewportSceneItem(
        id: "body",
        featureID: featureID,
        sceneNodeID: nodeID,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 1,
            sizeZMeters: 2,
            yMinMeters: 0,
            yMaxMeters: 1,
            topology: topology
        ))
    )
    let scene = ViewportScene(items: [item])
    let selection = SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: nodeID)])
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: .empty(),
        scene: scene,
        selection: selection,
        ruler: .standard(for: .meter),
        enabledRoutes: [.bodyTransform],
        interactiveRoutes: [.bodyTransform]
    )

    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            checkpoint: { _, _, _ in }
        )
    )
    #expect(source.worldLines.count == 15)
    #expect(source.worldLines.prefix(12).allSatisfy { $0.points.count == 2 })
    #expect(source.markers.count >= 15)
    #expect(source.cameraLines.count == 3)
    #expect(source.cameraPaths.isEmpty)

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var identities: [ViewportSpatialHandleIdentity] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSurfaceTransformAffordances(
        from: source,
        checkpoint: { _, _, _ in },
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        handleIdentities: &identities,
        activeFamilies: &families
    )
    #expect(families.contains(.transform))
    #expect(cameraLines.contains { line in
        line.value.points.contains { point in
            if case .projected = point.offset { return true }
            return false
        }
    })
    #expect(cameraLines.allSatisfy { $0.value.points.count == 2 })
}

@Test
func passiveSurfaceTransformRoutesDoNotRequireInteractiveCallbacks() throws {
    let display = ViewportSurfaceKnotDisplay(
        selectionReference: .curve(.whole(.init(featureID: FeatureID(), curveIndex: 0))),
        direction: .u,
        knotIndex: 0,
        value: 0.5,
        point: .origin,
        u: 0.5,
        v: 0.5
    )
    let item = ViewportSceneItem(
        id: "surface",
        featureID: FeatureID(),
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 1,
            sizeZMeters: 2,
            yMinMeters: 0,
            yMaxMeters: 1,
            surfaceKnotDisplays: [display]
        ))
    )
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: .empty(),
        scene: ViewportScene(items: [item]),
        selection: .empty,
        ruler: .standard(for: .meter),
        enabledRoutes: [.surfaceKnot],
        interactiveRoutes: []
    )
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            checkpoint: { _, _, _ in }
        )
    )
    #expect(source.markers.count == 1)
    #expect(source.markers[0].identity == nil)
}

@Test
func malformedConstructionFaceIsRefusedAsTypedFailure() throws {
    let nodeID = SceneNodeID()
    let target = SelectionTarget(
        sceneNodeID: nodeID,
        component: .face(.bodyFaceFront)
    )
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: .empty(),
        scene: ViewportScene(items: []),
        selection: .empty,
        ruler: .standard(for: .meter),
        enabledRoutes: [.constructionFace],
        interactiveRoutes: [],
        constructionFaceTarget: target
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            checkpoint: { _, _, _ in }
        )
    }
}

@Test
func surfaceTransformSourcePropagatesCheckpointCancellationBeforeAllocation() {
    struct Cancelled: Error {}
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: .empty(),
        scene: ViewportScene(items: []),
        selection: .empty,
        ruler: .standard(for: .meter),
        enabledRoutes: [.bodyTransform]
    )
    #expect(throws: Cancelled.self) {
        _ = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            checkpoint: { _, _, _ in throw Cancelled() }
        )
    }
}

@Test
func edgeFilletUsesFixedOriginAndExactDirectedHandleOffset() throws {
    let featureID = FeatureID()
    let nodeID = SceneNodeID()
    let topology = ViewportBodyTopology(
        edges: [
            .init(
                componentID: .bodyEdgeLeftBottom,
                start: Point3D(x: -1, y: 0, z: -1),
                end: Point3D(x: 1, y: 0, z: -1)
            ),
        ]
    )
    let item = ViewportSceneItem(
        id: "body",
        featureID: featureID,
        sceneNodeID: nodeID,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(component: ViewportBodyComponent(
            sizeXMeters: 2,
            sizeYMeters: 1,
            sizeZMeters: 2,
            yMinMeters: 0,
            yMaxMeters: 1,
            topology: topology
        ))
    )
    let target = SelectionTarget(sceneNodeID: nodeID, component: .edge(.bodyEdgeLeftBottom))
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: .empty(),
        scene: ViewportScene(items: [item]),
        selection: SelectionModel(selectedTargets: [target]),
        ruler: .standard(for: .meter),
        enabledRoutes: [.edgeFillet],
        interactiveRoutes: [.edgeFillet]
    )
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            checkpoint: { _, _, _ in }
        )
    )
    #expect(source.cameraLines.count == 1)
    #expect(source.cameraPaths.count == 1)
    #expect(source.labels.isEmpty)
    #expect(source.cameraLines[0].points[0].usesFixedOffset)
    #expect(source.cameraLines[0].points[0].anchor == source.cameraLines[0].points[1].anchor)
    #expect(source.cameraLines[0].points[1].minimumLength == nil)
    #expect(source.cameraLines[0].points[1].parallel == 18)

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var identities: [ViewportSpatialHandleIdentity] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSurfaceTransformAffordances(
        from: source,
        checkpoint: { _, _, _ in },
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        handleIdentities: &identities,
        activeFamilies: &families
    )
    #expect(cameraLines.count == 1)
    if cameraLines.count == 1,
       case .fixed(let originOffset) = cameraLines[0].value.points[0].offset {
        #expect(originOffset == .zero)
    } else if cameraLines.count == 1 {
        Issue.record("Fillet line origin must use a fixed zero camera offset.")
    }
    if cameraLines.count == 1,
       case .directed(_, let parallel, let perpendicular) = cameraLines[0].value.points[1].offset {
        #expect(parallel == 18)
        #expect(perpendicular == 0)
    } else if cameraLines.count == 1 {
        Issue.record("Fillet handle must use a directed 18 point offset.")
    }
}

@Test
func unsupportedEdgeFilletSelectionProducesNoHandle() throws {
    let nodeID = SceneNodeID()
    let target = SelectionTarget(
        sceneNodeID: nodeID,
        component: .edge(SelectionComponentID(rawValue: "unsupported.edge"))
    )
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: .empty(),
        scene: ViewportScene(items: []),
        selection: SelectionModel(selectedTargets: [target]),
        ruler: .standard(for: .meter),
        enabledRoutes: [.edgeFillet],
        interactiveRoutes: [.edgeFillet]
    )
    let source = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
        from: raw,
        checkpoint: { _, _, _ in }
    )
    #expect(source == nil)
}

@Test
func rawSurfaceTransformInputEmitsSelectedSurfaceControlTrimAndFrameRoles() throws {
    var document = DesignDocument.empty()
    let surfaceFeatureID = try document.createBSplineSurface(
        name: "Surface Transform Route Fixture",
        surface: testSurfaceTransformBSplineSurface()
    )
    let summary = try SurfaceSourceSummaryService().summarize(
        document: document,
        displayUnit: .millimeter
    )
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let controlReference = try #require(controlPoint.selectionReference)
    let faceReference = try #require(patch.faceSelectionReference)
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
    let trimFeatureID = try #require(
        document.existingSurfaceTrimOperation(for: surfaceFeatureID)?.node.id
    )
    let builtScene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let builtItem = try #require(builtScene.items.first { $0.featureID == trimFeatureID })
    guard case .body(var component) = builtItem.kind else {
        Issue.record("Expected an authored surface-trim body scene item.")
        return
    }
    let endpointDisplay = try #require(component.surfaceTrimEndpointDisplays.first)
    let trimControlDisplay = try #require(component.surfaceTrimControlPointDisplays.first)
    let trimReference = endpointDisplay.selectionReference
    let frameQuery = SurfaceFrameQuery(selectionReference: controlReference)
    let frameID = try SurfaceFrameDisplayID(query: frameQuery)

    component.surfaceControlPointDisplays = [
        ViewportSurfaceControlPointDisplay(
            selectionReference: controlReference,
            point: Point3D(x: controlPoint.point.x, y: controlPoint.point.y, z: controlPoint.point.z),
            uIndex: controlPoint.uIndex,
            vIndex: controlPoint.vIndex,
            isBoundary: controlPoint.isBoundary
        ),
    ]
    component.surfaceFrameDisplays = [
        ViewportSurfaceFrameDisplay(
            id: frameID,
            query: frameQuery,
            position: Point3D(x: controlPoint.point.x, y: controlPoint.point.y, z: controlPoint.point.z),
            uAxis: .unitX,
            vAxis: .unitY,
            normal: .unitZ,
            u: 0.5,
            v: 0.5,
            faceSubshapeIDs: []
        ),
    ]
    var item = builtItem
    item.kind = .body(component: component)
    let scene = ViewportScene(items: [item])
    let selection = SelectionModel(
        selectedReferences: [controlReference, trimReference]
    )
    let controlIdentity = ViewportSpatialHandleIdentity.surfaceControlPoint(
        .init(controlReference),
        role: .planar
    )
    let trimEndpointIdentity = ViewportSpatialHandleIdentity.surfaceTrimEndpoint(
        .init(trimReference),
        endpoint: endpointDisplay.endpoint
    )
    let trimControlIdentity = ViewportSpatialHandleIdentity.surfaceTrimControlPoint(
        .init(trimReference),
        index: trimControlDisplay.controlPointIndex
    )
    let frameIdentity = ViewportSpatialHandleIdentity.surfaceFrame(
        [.init(controlReference)],
        displayID: frameID,
        axis: .u
    )
    let routes: Set<ViewportSpatialOverlayProducer.SurfaceTransformAffordanceRoute> = [
        .surfaceControlPoint,
        .surfaceTrimEndpoint,
        .surfaceTrimControlPoint,
        .surfaceFrame,
    ]
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: document,
        scene: scene,
        selection: selection,
        ruler: .standard(for: .millimeter),
        enabledRoutes: routes,
        interactiveRoutes: routes,
        activeValues: [
            .init(identity: controlIdentity, delta: Vector3D(x: 0.001, y: 0.0, z: 0.0)),
            .init(identity: trimEndpointIdentity, delta: Vector3D(x: 0.0, y: 0.001, z: 0.0)),
            .init(identity: trimControlIdentity, delta: Vector3D(x: 0.0, y: 0.0, z: 0.001)),
            .init(identity: frameIdentity, distance: 0.01),
        ]
    )

    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            checkpoint: { _, _, _ in }
        )
    )
    #expect(source.markers.contains { $0.identity == controlIdentity })
    #expect(source.markers.contains { $0.identity == trimEndpointIdentity })
    #expect(source.markers.contains { $0.identity == trimControlIdentity })
    #expect(source.cameraLines.contains { $0.route == .surfaceFrame && $0.identity == frameIdentity })
    #expect(source.cameraPaths.contains { $0.route == .surfaceFrame && $0.identity == frameIdentity })
    #expect(source.labels.contains { $0.route == .surfaceFrame && $0.identity == frameIdentity })
    let controlPreview = try #require(source.worldLines.first {
        $0.route == .surfaceControlPoint && $0.identity == controlIdentity && $0.state == .active
    })
    let controlDelta = controlPreview.points[1] - controlPreview.points[0]
    #expect(controlPreview.points[0] == component.surfaceControlPointDisplays[0].point)
    #expect(abs(controlDelta.x - 0.001) <= 1.0e-12)
    #expect(abs(controlDelta.y) <= 1.0e-12)
    #expect(abs(controlDelta.z) <= 1.0e-12)
    let trimPreview = try #require(source.worldLines.first {
        $0.route == .surfaceTrimEndpoint && $0.identity == trimEndpointIdentity && $0.state == .active
    })
    let trimDelta = trimPreview.points[1] - trimPreview.points[0]
    #expect(trimPreview.points[0] == endpointDisplay.point)
    #expect(abs(trimDelta.x) <= 1.0e-12)
    #expect(abs(trimDelta.y - 0.001) <= 1.0e-12)
    #expect(abs(trimDelta.z) <= 1.0e-12)
    let framePreview = try #require(source.cameraLines.first {
        $0.route == .surfaceFrame && $0.identity == frameIdentity
    })
    let framePoint = framePreview.points[1]
    let frameDelta = framePoint.toward - framePoint.anchor
    #expect(framePoint.anchor == component.surfaceFrameDisplays[0].position)
    #expect(framePoint.minimumLength == 0)
    #expect(abs(frameDelta.x - 0.01) <= 1.0e-12)
    #expect(abs(frameDelta.y) <= 1.0e-12)
    #expect(abs(frameDelta.z) <= 1.0e-12)
    let frameLabel = try #require(source.labels.first {
        $0.route == .surfaceFrame && $0.identity == frameIdentity
    })
    let expectedFrameLabel = "U \(ViewportLengthLabelFormatter.string(fromMeters: 0.01, preferredUnit: raw.ruler.displayUnit))"
    #expect(frameLabel.text == expectedFrameLabel)
    #expect(frameLabel.placement.anchor == framePoint.anchor)
    #expect(frameLabel.placement.minimumLength == 0)
    #expect(frameLabel.placement.parallel == 8)
    #expect(frameLabel.placement.perpendicular == 18)

    let passiveFrameIdentity = ViewportSpatialHandleIdentity.surfaceFrame(
        [.init(controlReference)],
        displayID: frameID,
        axis: .v
    )
    let passiveFrame = try #require(source.cameraLines.first {
        $0.route == .surfaceFrame && $0.identity == passiveFrameIdentity
    })
    #expect(passiveFrame.points[1].minimumLength == nil)
    #expect(passiveFrame.points[1].parallel == 36)
    #expect(passiveFrame.points[1].perpendicular == 0)

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var identities: [ViewportSpatialHandleIdentity] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSurfaceTransformAffordances(
        from: source,
        checkpoint: { _, _, _ in },
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        handleIdentities: &identities,
        activeFamilies: &families
    )
    #expect(!meshes.isEmpty || !paths.isEmpty || !cameraLines.isEmpty || !cameraPaths.isEmpty || !labels.isEmpty || !markers.isEmpty)
    #expect(families.contains(.transform))
    #expect(identities.contains(controlIdentity))
    #expect(identities.contains(trimEndpointIdentity))
    #expect(identities.contains(trimControlIdentity))
    #expect(identities.contains(frameIdentity))

    let frameHandleIndex = UInt32(try #require(identities.firstIndex(of: frameIdentity)))
    let nativeFrameLine = try #require(cameraLines.first { $0.value.handleIndex == frameHandleIndex })
    guard nativeFrameLine.value.points.count >= 2 else {
        Issue.record("Surface frame native line did not retain its fixed origin and active tip.")
        return
    }
    switch nativeFrameLine.value.points[0].offset {
    case .fixed(let offset):
        #expect(offset == .zero)
    case .directed, .projected:
        Issue.record("Surface frame native line must begin at a fixed world anchor.")
    }
    switch nativeFrameLine.value.points[1].offset {
    case .projected(let toward, let minimumLength, let parallel, let perpendicular):
        #expect(toward == framePoint.toward)
        #expect(minimumLength == 0)
        #expect(parallel == 0)
        #expect(perpendicular == 0)
    case .fixed, .directed:
        Issue.record("Active surface frame tip must use projected native placement.")
    }
    let nativeFramePath = try #require(cameraPaths.first { $0.value.handleIndex == frameHandleIndex })
    switch nativeFramePath.value.offset {
    case .projected(let toward, let minimumLength, let parallel, let perpendicular):
        #expect(toward == framePoint.toward)
        #expect(minimumLength == 0)
        #expect(parallel == 0)
        #expect(perpendicular == 0)
    case .fixed, .directed:
        Issue.record("Active surface frame tip glyph must share projected tip placement.")
    }
    let nativeFrameLabel = try #require(labels.first { $0.value.handleIndex == frameHandleIndex })
    #expect(nativeFrameLabel.value.anchor == framePoint.anchor)
    switch nativeFrameLabel.value.offset {
    case .projected(let toward, let minimumLength, let parallel, let perpendicular):
        #expect(toward == framePoint.toward)
        #expect(minimumLength == 0)
        #expect(parallel == 8)
        #expect(perpendicular == 18)
    case .fixed, .directed:
        Issue.record("Active surface frame label must share projected tip direction.")
    }

    let passiveHandleIndex = UInt32(try #require(identities.firstIndex(of: passiveFrameIdentity)))
    let nativePassiveLine = try #require(cameraLines.first { $0.value.handleIndex == passiveHandleIndex })
    guard nativePassiveLine.value.points.count >= 2 else {
        Issue.record("Passive surface frame native line did not retain its fixed origin and tip.")
        return
    }
    switch nativePassiveLine.value.points[1].offset {
    case .directed(_, let parallel, let perpendicular):
        #expect(parallel == 36)
        #expect(perpendicular == 0)
    case .fixed, .projected:
        Issue.record("Passive surface frame tip must use fixed-point directed placement.")
    }
}

@Test
func rawSurfaceTransformInputEmitsPolySplineVertexSlidePreview() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "PolySpline Surface Transform Route Fixture",
        sourceMesh: testSurfaceTransformPolySplineMesh(),
        options: PolySplineOptions(mergePatches: false)
    )
    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let body = try #require(scene.items.first { $0.featureID == featureID })
    guard case .body(let component) = body.kind,
          let topology = component.topology,
          let sceneNodeID = body.sceneNodeID else {
        Issue.record("Expected a PolySpline body topology scene item.")
        return
    }
    let vertex = try #require(topology.vertices.first { vertex in
        vertex.componentID.generatedTopologySubshapeID?.role.hasPrefix("polySpline.vertex") == true
    })
    let target = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(vertex.componentID)
    )
    let direction = PolySplineSurfaceVertexSlideDirection.positiveU
    let slideIdentity = ViewportSpatialHandleIdentity.polySplineSurfaceVertexSlide(
        .init(targets: [target], direction: direction)
    )
    let routes: Set<ViewportSpatialOverlayProducer.SurfaceTransformAffordanceRoute> = [
        .polySplineSurfaceVertex,
        .polySplineSurfaceVertexSlide,
        .activePolySplineSurfaceVertexPreview,
    ]
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [target]),
        ruler: .standard(for: .millimeter),
        enabledRoutes: routes,
        interactiveRoutes: routes,
        activeValues: [
            .init(identity: slideIdentity, distance: 0.001, showsOriginalComparison: true),
        ]
    )

    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            checkpoint: { _, _, _ in }
        )
    )
    #expect(source.markers.contains { marker in
        guard let identity = marker.identity,
              case .polySplineSurfaceVertex(let valueFeatureID, let componentID, .planar) = identity else {
            return false
        }
        return valueFeatureID == featureID && componentID == vertex.componentID
    })
    #expect(source.cameraLines.contains { $0.route == .polySplineSurfaceVertexSlide && $0.identity == slideIdentity })
    #expect(source.worldLines.contains { $0.route == .activePolySplineSurfaceVertexPreview && $0.identity == slideIdentity })
    #expect(source.markers.contains { $0.route == .activePolySplineSurfaceVertexPreview && $0.identity == slideIdentity })
    #expect(source.meshes.contains { $0.route == .activePolySplineSurfaceVertexPreview && $0.identity == slideIdentity })
    let preview = try #require(source.worldLines.first {
        $0.route == .activePolySplineSurfaceVertexPreview && $0.identity == slideIdentity
    })
    let displacement = preview.points[1] - preview.points[0]
    #expect(preview.points[0] == vertex.point)
    #expect(abs(displacement.length - 0.001) <= 1.0e-12)

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var identities: [ViewportSpatialHandleIdentity] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSurfaceTransformAffordances(
        from: source,
        checkpoint: { _, _, _ in },
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        handleIdentities: &identities,
        activeFamilies: &families
    )
    #expect(!meshes.isEmpty)
    #expect(!cameraLines.isEmpty)
    #expect(families.contains(.transform))
    #expect(identities.contains(slideIdentity))
}

@Test
func rawSurfaceTransformInputEmitsConstructionPlaneAndSketchTransform() throws {
    var document = DesignDocument.empty()
    let planeID = try document.createConstructionPlane(
        name: "Surface Transform Construction Plane",
        plane: .xy
    )
    let planeEntry = try #require(
        ConstructionPlaneSummaryService().summarize(document: document, activePlaneID: nil)
            .planes.first { $0.id == planeID }
    )
    let planeTarget = try #require(planeEntry.selectionTarget())
    let sketchFeatureID = FeatureID()
    let sketchNodeID = SceneNodeID()
    let sketchTarget = SelectionTarget(sceneNodeID: sketchNodeID)
    let sketchItem = ViewportSceneItem(
        id: "sketch-transform",
        featureID: sketchFeatureID,
        sceneNodeID: sketchNodeID,
        modelBounds: CGRect(x: -1.0, y: -0.5, width: 2.0, height: 1.0),
        kind: .sketch(primitives: [])
    )
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: document,
        scene: ViewportScene(items: [sketchItem]),
        selection: SelectionModel(selectedTargets: [planeTarget, sketchTarget]),
        ruler: .standard(for: .meter),
        enabledRoutes: [.constructionPlane, .sketchTransform],
        interactiveRoutes: [.constructionPlane, .sketchTransform]
    )

    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            checkpoint: { _, _, _ in }
        )
    )
    #expect(source.worldLines.contains { $0.route == .constructionPlane && $0.closed })
    #expect(source.worldLines.contains { $0.route == .constructionPlane && $0.identity != nil })
    #expect(source.worldLines.contains { $0.route == .sketchTransform && $0.closed })
    #expect(source.worldLines.filter { $0.route == .sketchTransform && $0.identity != nil }.count == 3)
    #expect(source.cameraLines.contains { $0.route == .sketchTransform })
    #expect(source.markers.contains { $0.route == .constructionPlane && $0.identity != nil })
    #expect(source.markers.contains { $0.route == .sketchTransform })

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var identities: [ViewportSpatialHandleIdentity] = []
    var families: Set<ViewportSpatialOverlayFamily> = []
    try ViewportSpatialOverlayProducer.appendSurfaceTransformAffordances(
        from: source,
        checkpoint: { _, _, _ in },
        meshes: &meshes,
        paths: &paths,
        labels: &labels,
        markers: &markers,
        cameraLines: &cameraLines,
        cameraPaths: &cameraPaths,
        handleIdentities: &identities,
        activeFamilies: &families
    )
    #expect(!meshes.isEmpty)
    #expect(!cameraLines.isEmpty)
    #expect(families.contains(.construction))
    #expect(families.contains(.transform))
}

private func testSurfaceTransformBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
}

private func testSurfaceTransformPolySplineMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: 0.0),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}
