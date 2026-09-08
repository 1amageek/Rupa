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

    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    )
    // The twelve bounds edges are the only world polylines left: the three
    // rotation rings became camera lines when the ring radius became a screen
    // length, so the camera lines are three axis arrows plus three rings.
    #expect(source.worldLines.count == 12)
    #expect(source.worldLines.allSatisfy { $0.points.count == 2 })
    #expect(source.markers.count >= 15)
    #expect(source.cameraLines.count == 6)
    #expect(source.cameraPaths.isEmpty)
    let bodyRecord = try #require(interactionRecords.first { record in
        guard case .affordance(let target, _, _) = record.target else { return false }
        return target.featureID == featureID
    })
    guard case .affordance(let bodyTarget, let members, let groupEdit) = bodyRecord.target else {
        Issue.record("Body transform record did not retain its prepared affordance baseline.")
        return
    }
    #expect(bodyTarget.featureID == featureID)
    #expect(members.count == 1)
    #expect(members[0].occurrenceID == item.id)
    #expect(members[0].featureID == featureID)
    #expect(members[0].sceneNodeID == nodeID)
    #expect(members[0].edit == ViewportObjectEditState(item: item))
    #expect(groupEdit == nil)
    #expect(bodyRecord.occurrenceID == item.id)

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
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
        interactionRecords: &interactionRecords,
        activeFamilies: &families
    )
    #expect(families.contains(.transform))
    // A body transform arrow is pinned on screen, so its end point is
    // direction-relative rather than projected; a ring sample advances in scene
    // space so the ring keeps its foreshortening.
    #expect(cameraLines.allSatisfy { line in
        line.value.points.allSatisfy { point in
            switch point.offset {
            case .fixed, .directed, .worldDirected: return true
            case .projected: return false
            }
        }
    })
    #expect(cameraLines.filter { $0.value.points.count == 2 }.count == 3)
    #expect(cameraLines.filter { $0.value.points.count == 13 }.count == 3)
}

@Test
func bodyTransformCapturesOccurrenceScopedBaselinesAndGroupSnapshot() throws {
    let featureID = FeatureID()
    let firstNodeID = SceneNodeID()
    let secondNodeID = SceneNodeID()
    func bodyItem(id: String, nodeID: SceneNodeID, bounds: CGRect) -> ViewportSceneItem {
        ViewportSceneItem(
            id: id,
            featureID: featureID,
            sceneNodeID: nodeID,
            modelBounds: bounds,
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: Double(bounds.width),
                sizeYMeters: 1,
                sizeZMeters: Double(bounds.height),
                yMinMeters: 0,
                yMaxMeters: 1
            ))
        )
    }
    let first = bodyItem(id: "body-occurrence-1", nodeID: firstNodeID, bounds: CGRect(x: -1, y: -1, width: 2, height: 2))
    let second = bodyItem(id: "body-occurrence-2", nodeID: secondNodeID, bounds: CGRect(x: 3, y: 2, width: 4, height: 5))
    let baseline = ViewportObjectEditState(
        xMin: -4, xMax: 4, yMin: -2, yMax: 2, zMin: -3, zMax: 3
    )
    var editedBodies: [FeatureID: ViewportObjectEditState] = [featureID: baseline]
    let raw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: .empty(),
        scene: ViewportScene(items: [first, second]),
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstNodeID),
            SelectionTarget(sceneNodeID: secondNodeID),
        ]),
        editedBodies: editedBodies,
        ruler: .standard(for: .meter),
        enabledRoutes: [.bodyTransform],
        interactiveRoutes: [.bodyTransform]
    )
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    _ = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    )
    editedBodies[featureID] = ViewportObjectEditState(
        xMin: -9, xMax: 9, yMin: -8, yMax: 8, zMin: -7, zMax: 7
    )
    let bodyRecord = try #require(interactionRecords.first { record in
        guard case .affordance(_, let members, let groupEdit) = record.target else { return false }
        return members.count == 2 && groupEdit != nil
    })
    guard case .affordance(let target, let members, let groupEdit) = bodyRecord.target else {
        Issue.record("Grouped body transform did not retain its occurrence-scoped baseline.")
        return
    }
    #expect(target.featureID == featureID)
    #expect(bodyRecord.occurrenceID == nil)
    #expect(members.map(\.occurrenceID) == [first.id, second.id])
    #expect(members.map(\.featureID) == [featureID, featureID])
    #expect(members[0].sceneNodeID == firstNodeID)
    #expect(members[1].sceneNodeID == secondNodeID)
    #expect(members.map(\.edit) == [baseline, baseline])
    #expect(groupEdit?.xMin == baseline.xMin)
    #expect(groupEdit?.xMax == baseline.xMax)
    #expect(groupEdit?.yMin == baseline.yMin)
    #expect(groupEdit?.yMax == baseline.yMax)
    #expect(groupEdit?.zMin == baseline.zMin)
    #expect(groupEdit?.zMax == baseline.zMax)

    let replacement = ViewportObjectEditState(
        xMin: -9, xMax: 9, yMin: -8, yMax: 8, zMin: -7, zMax: 7
    )
    let replacementRaw = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput(
        document: .empty(),
        scene: ViewportScene(items: [first]),
        selection: SelectionModel(selectedTargets: [SelectionTarget(sceneNodeID: firstNodeID)]),
        editedBodies: [featureID: replacement],
        ruler: .standard(for: .meter),
        enabledRoutes: [.bodyTransform],
        interactiveRoutes: [.bodyTransform]
    )
    var replacementRecords: [ViewportSpatialInteractionRecord] = []
    _ = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: replacementRaw,
            interactionRecords: &replacementRecords,
            checkpoint: { _, _, _ in }
        )
    )
    let replacementRecord = try #require(replacementRecords.first { record in
        guard case .affordance(_, let members, let groupEdit) = record.target else { return false }
        return members.count == 1 && groupEdit == nil
    })
    guard case .affordance(_, let replacementMembers, let replacementGroupEdit) = replacementRecord.target else {
        Issue.record("Single body replacement did not retain its source edit baseline.")
        return
    }
    #expect(replacementRecord.occurrenceID == first.id)
    #expect(replacementMembers.count == 1)
    #expect(replacementMembers[0].occurrenceID == first.id)
    #expect(replacementMembers[0].edit == replacement)
    #expect(replacementGroupEdit == nil)
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
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
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
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
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
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    #expect(throws: Cancelled.self) {
        _ = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
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
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
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
    #expect(source.cameraLines[0].hitTolerancePoints == nil)
    #expect(source.cameraPaths[0].hitTolerancePoints == 10.0)
    #expect(source.cameraPaths[0].occurrenceID == item.id)
    #expect(interactionRecords.contains {
        $0.identity == .affordance(.init(
            featureID: featureID,
            selectionTarget: target,
            action: .profileEdgeFillet(target, .leftBottom)
        )) && $0.occurrenceID == item.id
    })
    let filletRecord = try #require(interactionRecords.first {
        $0.identity == .affordance(.init(
            featureID: featureID,
            selectionTarget: target,
            action: .profileEdgeFillet(target, .leftBottom)
        )) && $0.occurrenceID == item.id
    })
    guard case .affordance(let filletTarget, let filletMembers, let filletGroupEdit) = filletRecord.target else {
        Issue.record("Edge fillet record did not retain its body baseline.")
        return
    }
    #expect(filletTarget.featureID == featureID)
    #expect(filletMembers.count == 1)
    #expect(filletMembers[0].occurrenceID == item.id)
    #expect(filletMembers[0].featureID == featureID)
    #expect(filletMembers[0].sceneNodeID == nodeID)
    #expect(filletMembers[0].edit == ViewportObjectEditState(item: item))
    #expect(filletGroupEdit == nil)
    #expect(interactionRecords.first(where: {
        $0.identity == .affordance(.init(
            featureID: featureID,
            selectionTarget: target,
            action: .profileEdgeFillet(target, .leftBottom)
        )) && $0.occurrenceID == item.id
    })?.modelTransform == item.modelTransform)

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
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
        interactionRecords: &interactionRecords,
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
    let filletHandleIndex = UInt32(try #require(interactionRecords.firstIndex {
        $0.identity == .affordance(.init(
            featureID: featureID,
            selectionTarget: target,
            action: .profileEdgeFillet(target, .leftBottom)
        )) && $0.occurrenceID == item.id
    }))
    #expect(cameraLines[0].value.handleIndex == nil)
    #expect(cameraPaths[0].value.handleIndex == filletHandleIndex)
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
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
        from: raw,
        interactionRecords: &interactionRecords,
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

    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    )
    #expect(source.markers.contains { $0.identity == controlIdentity })
    #expect(source.markers.contains { $0.identity == trimEndpointIdentity })
    #expect(source.markers.contains { $0.identity == trimControlIdentity })
    #expect(source.cameraLines.contains { $0.route == .surfaceFrame && $0.identity == frameIdentity })
    #expect(source.cameraPaths.contains { $0.route == .surfaceFrame && $0.identity == frameIdentity })
    #expect(source.labels.contains { $0.route == .surfaceFrame && $0.identity == nil })
    let controlAxisIdentity = ViewportSpatialHandleIdentity.surfaceControlPoint(
        .init(controlReference),
        role: .axis(.x)
    )
    let controlAxis = try #require(source.cameraLines.first {
        $0.route == .surfaceControlPoint && $0.identity == controlAxisIdentity
    })
    #expect(controlAxis.points[0].parallel == 16)
    #expect(controlAxis.points[0].minimumLength == nil)
    #expect(controlAxis.points[1].minimumLength == 16)
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
    let expectedFrameLabel = "U \(ViewportLengthLabelFormatter.string(fromMeters: 0.01, preferredUnit: raw.ruler.displayUnit))"
    let frameLabel = try #require(source.labels.first {
        $0.route == .surfaceFrame && $0.text == expectedFrameLabel
    })
    #expect(frameLabel.identity == nil)
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
        interactionRecords: &interactionRecords,
        activeFamilies: &families
    )
    #expect(!meshes.isEmpty || !paths.isEmpty || !cameraLines.isEmpty || !cameraPaths.isEmpty || !labels.isEmpty || !markers.isEmpty)
    #expect(families.contains(.transform))
    #expect(interactionRecords.contains { $0.identity == controlIdentity })
    #expect(interactionRecords.contains { $0.identity == trimEndpointIdentity })
    #expect(interactionRecords.contains { $0.identity == trimControlIdentity })
    #expect(interactionRecords.contains { $0.identity == frameIdentity })

    let controlAxisHandleIndex = UInt32(try #require(interactionRecords.firstIndex {
        $0.identity == controlAxisIdentity
    }))
    let nativeControlAxis = try #require(cameraLines.first {
        $0.value.handleIndex == controlAxisHandleIndex
    })
    guard nativeControlAxis.value.points.count >= 2 else {
        Issue.record("Surface control-point axis native line did not retain its two-point footprint.")
        return
    }
    switch nativeControlAxis.value.points[0].offset {
    case .directed(_, let parallel, let perpendicular):
        #expect(parallel == 16)
        #expect(perpendicular == 0)
    case .fixed, .projected, .worldDirected:
        Issue.record("Surface control-point axis start must use a directed 16 point gap.")
    }
    switch nativeControlAxis.value.points[1].offset {
    case .projected(_, let minimumLength, let parallel, let perpendicular):
        #expect(minimumLength == 16)
        #expect(parallel == 0)
        #expect(perpendicular == 0)
    case .fixed, .directed, .worldDirected:
        Issue.record("Surface control-point axis tip must retain its 16 point minimum length.")
    }

    let frameHandleIndex = UInt32(try #require(interactionRecords.firstIndex { $0.identity == frameIdentity }))
    let nativeFrameLine = try #require(cameraLines.first { $0.value.handleIndex == frameHandleIndex })
    guard nativeFrameLine.value.points.count >= 2 else {
        Issue.record("Surface frame native line did not retain its fixed origin and active tip.")
        return
    }
    switch nativeFrameLine.value.points[0].offset {
    case .directed(_, let parallel, let perpendicular):
        #expect(parallel == 10)
        #expect(perpendicular == 0)
    case .fixed, .projected, .worldDirected:
        Issue.record("Active surface frame native line must preserve its directed start gap.")
    }
    switch nativeFrameLine.value.points[1].offset {
    case .projected(let toward, let minimumLength, let parallel, let perpendicular):
        #expect(toward == framePoint.toward)
        #expect(minimumLength == 0)
        #expect(parallel == 0)
        #expect(perpendicular == 0)
    case .fixed, .directed, .worldDirected:
        Issue.record("Active surface frame tip must use projected native placement.")
    }
    let nativeFramePath = try #require(cameraPaths.first { $0.value.handleIndex == frameHandleIndex })
    switch nativeFramePath.value.offset {
    case .projected(let toward, let minimumLength, let parallel, let perpendicular):
        #expect(toward == framePoint.toward)
        #expect(minimumLength == 0)
        #expect(parallel == 0)
        #expect(perpendicular == 0)
    case .fixed, .directed, .worldDirected:
        Issue.record("Active surface frame tip glyph must share projected tip placement.")
    }
    #expect(labels.contains { $0.value.handleIndex == nil && $0.value.text.hasPrefix("U ") })

    let passiveHandleIndex = UInt32(try #require(interactionRecords.firstIndex { $0.identity == passiveFrameIdentity }))
    let nativePassiveLine = try #require(cameraLines.first { $0.value.handleIndex == passiveHandleIndex })
    guard nativePassiveLine.value.points.count >= 2 else {
        Issue.record("Passive surface frame native line did not retain its fixed origin and tip.")
        return
    }
    switch nativePassiveLine.value.points[1].offset {
    case .directed(_, let parallel, let perpendicular):
        #expect(parallel == 36)
        #expect(perpendicular == 0)
    case .fixed, .projected, .worldDirected:
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

    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
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
    let vertexAxisIdentity = ViewportSpatialHandleIdentity.polySplineSurfaceVertex(
        featureID: featureID,
        componentID: vertex.componentID,
        role: .axis(.x)
    )
    let vertexAxis = try #require(source.cameraLines.first {
        $0.route == .polySplineSurfaceVertex && $0.identity == vertexAxisIdentity
    })
    #expect(vertexAxis.points[0].parallel == 16)
    #expect(vertexAxis.points[0].minimumLength == nil)
    #expect(vertexAxis.points[1].minimumLength == 16)
    #expect(source.cameraPaths.contains {
        $0.route == .polySplineSurfaceVertexSlide
            && $0.identity == slideIdentity
            && $0.hitTolerancePoints == 14.0
    })
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
        interactionRecords: &interactionRecords,
        activeFamilies: &families
    )
    #expect(!meshes.isEmpty)
    #expect(!cameraLines.isEmpty)
    #expect(families.contains(.transform))
    #expect(interactionRecords.contains { $0.identity == slideIdentity })
    let vertexAxisHandleIndex = UInt32(try #require(interactionRecords.firstIndex {
        $0.identity == vertexAxisIdentity
    }))
    let nativeVertexAxis = try #require(cameraLines.first {
        $0.value.handleIndex == vertexAxisHandleIndex
    })
    guard nativeVertexAxis.value.points.count >= 2 else {
        Issue.record("PolySpline vertex axis native line did not retain its two-point footprint.")
        return
    }
    switch nativeVertexAxis.value.points[0].offset {
    case .directed(_, let parallel, let perpendicular):
        #expect(parallel == 16)
        #expect(perpendicular == 0)
    case .fixed, .projected, .worldDirected:
        Issue.record("PolySpline vertex axis start must use a directed 16 point gap.")
    }
    switch nativeVertexAxis.value.points[1].offset {
    case .projected(_, let minimumLength, let parallel, let perpendicular):
        #expect(minimumLength == 16)
        #expect(parallel == 0)
        #expect(perpendicular == 0)
    case .fixed, .directed, .worldDirected:
        Issue.record("PolySpline vertex axis tip must retain its 16 point minimum length.")
    }
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

    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    )
    #expect(source.worldLines.contains { $0.route == .constructionPlane && $0.closed })
    #expect(source.worldLines.contains { $0.route == .constructionPlane && $0.identity != nil })
    #expect(source.worldLines.contains { $0.route == .sketchTransform && $0.closed })
    #expect(source.worldLines.filter { $0.route == .sketchTransform && $0.identity != nil }.count == 3)
    #expect(source.cameraLines.contains { $0.route == .sketchTransform })
    #expect(source.cameraLines.filter { $0.route == .sketchTransform }.allSatisfy { $0.hitTolerancePoints == nil })
    #expect(source.worldLines.filter { $0.route == .sketchTransform }.allSatisfy { $0.hitTolerancePoints == nil })
    #expect(!interactionRecords.contains { record in
        guard case .affordance(let target, _, _) = record.target else { return false }
        return target.featureID == sketchFeatureID
    })
    #expect(source.markers.contains { $0.route == .constructionPlane && $0.identity != nil })
    #expect(source.markers.contains { $0.route == .sketchTransform })

    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
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
        interactionRecords: &interactionRecords,
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
