import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

private typealias ProfileRoute = ViewportSpatialOverlayProducer.SurfaceTransformAffordanceRoute
private typealias ProfileRawInput =
    ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource.RawInput
private typealias ProfileMetrics = ViewportSpatialOverlayProducer.ProfileAffordanceMetrics

@Test
func profileFaceHandleDrawsOnTheFaceAnchorWithAFixedFootprint() throws {
    let featureID = FeatureID()
    let nodeID = SceneNodeID()
    let item = profileBodyItem(featureID: featureID, nodeID: nodeID, topology: ViewportBodyTopology())
    let target = SelectionTarget(sceneNodeID: nodeID, component: .face(.bodyFaceFront))
    let raw = profileRawInput(item: item, targets: [target], routes: [.profileFace])
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    )

    // A face centre projects onto the body centre from the most common camera,
    // so this handle carries no leader line and no inward offset at all.
    #expect(source.cameraLines.isEmpty)
    #expect(source.labels.isEmpty)
    #expect(source.markers.isEmpty)
    #expect(source.cameraPaths.count == 1)

    let path = try #require(source.cameraPaths.first)
    let edit = ViewportObjectEditState(item: item)
    #expect(path.placement.usesFixedOffset)
    #expect(path.placement.parallel == 0)
    #expect(path.placement.perpendicular == 0)
    #expect(path.placement.anchor == edit.worldPoint(edit.position(for: .front)))
    #expect(path.hitTolerancePoints == Float(ProfileMetrics.hitTolerancePoints))
    #expect(path.occurrenceID == item.id)

    let expectedIdentity = ViewportSpatialHandleIdentity.affordance(
        ViewportAffordanceTarget(
            featureID: featureID,
            selectionTarget: target,
            action: .profileFaceMove(target, .front)
        )
    )
    #expect(path.identity == expectedIdentity)
    let recordIndex = try #require(
        interactionRecords.firstIndex {
            $0.identity == expectedIdentity && $0.occurrenceID == item.id
        }
    )

    var output = ProfileAffordanceOutput()
    try output.append(from: source, interactionRecords: &interactionRecords)

    #expect(output.cameraLines.isEmpty)
    #expect(output.cameraPaths.count == 1)
    let drawn = try #require(output.cameraPaths.first).value
    #expect(drawn.handleIndex == UInt32(recordIndex))
    #expect(drawn.hitTolerancePoints == Float(ProfileMetrics.hitTolerancePoints))
    #expect(drawn.anchor == edit.worldPoint(edit.position(for: .front)))
    if case .fixed(let offset) = drawn.offset {
        #expect(offset == .zero)
    } else {
        Issue.record("A profile face handle must use a fixed zero camera offset.")
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func profileCornerHandlesAnchorEveryGeneratedVertexWithoutAnOffset() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        evaluationPolicy: .evaluateOnDemand
    )
    let item = try #require(
        scene.items.first {
            guard case .body = $0.kind else { return false }
            return $0.featureID == bodyFeatureID
        }
    )
    guard case .body(let component) = item.kind else {
        Issue.record("The extrude item is not a body item.")
        return
    }
    let topology = try #require(component.topology)
    #expect(!topology.vertices.isEmpty)

    let sceneNodeID = try #require(item.sceneNodeID)
    let targets = topology.vertices.map {
        SelectionTarget(sceneNodeID: sceneNodeID, component: .vertex($0.componentID))
    }
    let raw = ProfileRawInput(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: targets),
        ruler: .standard(for: .meter),
        enabledRoutes: [.profileCorner],
        interactiveRoutes: [.profileCorner]
    )
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    )

    #expect(source.cameraLines.isEmpty)
    #expect(source.cameraPaths.count == targets.count)

    let edit = ViewportObjectEditState(item: item)
    var seenVertices: Set<ViewportBodyVertex> = []
    var anchors: [Point3D] = []
    for path in source.cameraPaths {
        #expect(path.placement.usesFixedOffset)
        #expect(path.placement.parallel == 0)
        #expect(path.placement.perpendicular == 0)
        #expect(path.hitTolerancePoints == Float(ProfileMetrics.hitTolerancePoints))
        #expect(path.occurrenceID == item.id)
        guard case .affordance(let affordance) = path.identity,
              case .profileCornerMove(_, let vertex) = affordance.action else {
            Issue.record("A profile corner path must carry a corner-move affordance identity.")
            continue
        }
        seenVertices.insert(vertex)
        anchors.append(path.placement.anchor)
        #expect(path.placement.anchor == edit.worldPoint(edit.position(for: vertex)))
    }

    // Every selected CAD vertex resolves to its own corner of the edited box,
    // so no two corner handles land on one point.
    #expect(seenVertices.count == targets.count)
    for first in anchors.indices {
        for second in anchors.indices where second > first {
            #expect(anchors[first] != anchors[second])
        }
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func profileEdgeHandlesSeparateFilletAndChamferByFixedScreenOffsets() throws {
    // The two edge handles share one anchor, so only their fixed screen offsets
    // keep their footprints apart.
    #expect(
        ProfileMetrics.chamferOffsetPoints - ProfileMetrics.filletOffsetPoints
            >= 2 * ProfileMetrics.hitTolerancePoints
    )
    #expect(
        2 * ProfileMetrics.markRadiusPoints
            < ProfileMetrics.chamferOffsetPoints - ProfileMetrics.filletOffsetPoints
    )

    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: .standard(for: .meter))
    let item = try #require(scene.items.first { $0.featureID == featureID })
    let nodeID = try #require(item.sceneNodeID)
    guard case .body(let body) = item.kind else { Issue.record("Expected body"); return }
    let edges = try #require(body.topology?.edges)
    #expect(edges.count == 12)
    for edge in edges {
        let target = SelectionTarget(sceneNodeID: nodeID, component: .edge(edge.componentID))
        let raw = ProfileRawInput(document: session.document, scene: scene,
            selection: .init(selectedTargets: [target]), ruler: .standard(for: .meter),
            enabledRoutes: [.edgeFillet, .profileEdgeChamfer], interactiveRoutes: [.edgeFillet, .profileEdgeChamfer])
        var interactionRecords: [ViewportSpatialInteractionRecord] = []
        let source = try #require(
            try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
                from: raw,
                interactionRecords: &interactionRecords,
                checkpoint: { _, _, _ in }
            )
        )

        #expect(source.cameraLines.count == 2)
        #expect(source.cameraPaths.count == 2)

        let edit = ViewportObjectEditState(item: item)
        let anchor = Point3D(x: (edge.start.x + edge.end.x) * 0.5,
            y: (edge.start.y + edge.end.y) * 0.5, z: (edge.start.z + edge.end.z) * 0.5)
        let toward = edit.worldPoint(edit.centerPoint)
        let frame = ViewportEdgeTreatmentDragFrame(anchor: anchor, modelTransform: item.modelTransform)
        let expected: [(ViewportAffordanceAction, CGFloat)] = [
            (.profileEdgeFillet(target, frame), ProfileMetrics.filletOffsetPoints),
            (.profileEdgeChamfer(target, frame), ProfileMetrics.chamferOffsetPoints),
        ]
        for (action, offsetPoints) in expected {
            let identity = ViewportSpatialHandleIdentity.affordance(
                ViewportAffordanceTarget(
                    featureID: featureID,
                    selectionTarget: target,
                    action: action
                )
            )
            let path = try #require(source.cameraPaths.first { $0.identity == identity })
            #expect(!path.placement.usesFixedOffset)
            #expect(path.placement.minimumLength == nil)
            #expect(path.placement.parallel == offsetPoints)
            #expect(path.placement.perpendicular == 0)
            #expect(path.placement.anchor == anchor)
            #expect(path.placement.toward == toward)
            #expect(path.hitTolerancePoints == Float(ProfileMetrics.hitTolerancePoints))

            let line = try #require(
                source.cameraLines.first {
                    $0.points.count == 2 && $0.points[1].parallel == offsetPoints
                }
            )
            #expect(line.identity == nil)
            #expect(line.hitTolerancePoints == nil)
            #expect(line.points[0].usesFixedOffset)
            #expect(line.points[0].anchor == anchor)
            #expect(line.points[1].anchor == anchor)
            #expect(interactionRecords.contains { $0.identity == identity && $0.occurrenceID == item.id })
        }

        // The fillet is emitted first, so an equal-distance hit resolves to it.
        let filletIndex = try #require(
            interactionRecords.firstIndex {
                guard case .affordance(let affordance) = $0.identity else { return false }
                return affordance.action == .profileEdgeFillet(target, frame)
            }
        )
        let chamferIndex = try #require(
            interactionRecords.firstIndex {
                guard case .affordance(let affordance) = $0.identity else { return false }
                return affordance.action == .profileEdgeChamfer(target, frame)
            }
        )
        #expect(filletIndex < chamferIndex)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func selectedBoundaryEdgeShowsSurfaceFillForADeletedFaceOpening() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let solidFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let solidNodeID = try #require(session.document.productMetadata.sceneNodes.first { _, node in
        node.reference?.featureID == solidFeatureID
    }?.key)
    let solidTopology = try TopologySnapshotService().snapshot(document: session.document)
    let lateralFace = try #require(solidTopology.entries.first {
        $0.kind == .face
            && $0.sceneNodeID == solidNodeID.description
            && $0.generatedRole == "sideFace"
    }?.selectionTarget())
    _ = try session.execute(.deleteBodyFaces(targets: [lateralFace]))

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter)
    )
    let item = try #require(scene.items.first { $0.featureID == featureID })
    let nodeID = try #require(item.sceneNodeID)
    guard case .body(let body) = item.kind else {
        Issue.record("The open shell was not projected as a CAD body.")
        return
    }
    let loopEdges = try #require(body.topology?.edges.filter { $0.openBoundaryLoopID != nil })
    #expect(loopEdges.count == 4)
    let loopID = try #require(loopEdges.first?.openBoundaryLoopID)
    #expect(loopEdges.allSatisfy { $0.openBoundaryLoopID == loopID })
    let curvedEdge = try #require(loopEdges.first { $0.displayPoints.count > 2 })

    let edgeTarget = SelectionTarget(sceneNodeID: nodeID, component: .edge(loopEdges[0].componentID))
    var raw = ProfileRawInput(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [edgeTarget]),
        ruler: .standard(for: .meter),
        enabledRoutes: [.boundarySurface, .edgeFillet, .profileEdgeChamfer],
        interactiveRoutes: [.boundarySurface, .edgeFillet, .profileEdgeChamfer]
    )
    raw.edgeTreatmentHoverTarget = edgeTarget
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    )

    #expect(source.cameraLines.filter { $0.route == .boundarySurface }.count == loopEdges.count + 1)
    let curvedHighlight = try #require(source.cameraLines.first {
        $0.route == .boundarySurface && $0.points.count == curvedEdge.displayPoints.count
    })
    #expect(curvedHighlight.points.map(\.anchor) == curvedEdge.displayPoints.map(
        item.modelTransform.point
    ))
    #expect(source.cameraPaths.count == 1)
    guard case .affordance(let affordance) = try #require(source.cameraPaths.first).identity else {
        Issue.record("The fill glyph must be an addressable affordance.")
        return
    }
    #expect(affordance.selectionTarget == edgeTarget)
    #expect(affordance.action == .boundarySurface(edgeTarget))
    #expect(interactionRecords.count == 1)
    #expect(interactionRecords.first?.identity == .affordance(affordance))
    #expect(raw.selection.selectedTargets == [edgeTarget])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func selectedBoundaryEdgeOffersBoundarySurfaceBridgeForASingleFaceOuterPerimeter() throws {
    let session = EditorSession()
    let surface = BSplineSurface3D.bilinearPatch(
        bottomLeft: .origin,
        bottomRight: Point3D(x: 0.1, y: 0, z: 0),
        topRight: Point3D(x: 0.1, y: 0.1, z: 0),
        topLeft: Point3D(x: 0, y: 0.1, z: 0)
    )
    _ = try session.execute(.createBSplineSurface(name: "Open surface", surface: surface))
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter)
    )
    let item = try #require(scene.items.first { $0.featureID == featureID })
    let nodeID = try #require(item.sceneNodeID)
    guard case .body(let body) = item.kind,
          let edge = body.topology?.edges.first else {
        Issue.record("The source surface edge was not projected.")
        return
    }
    let edgeTarget = SelectionTarget(sceneNodeID: nodeID, component: .edge(edge.componentID))
    var raw = ProfileRawInput(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [edgeTarget]),
        ruler: .standard(for: .meter),
        enabledRoutes: [.boundarySurface],
        interactiveRoutes: [.boundarySurface]
    )
    raw.edgeTreatmentHoverTarget = edgeTarget
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    let source = try #require(
        try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    )

    #expect(source.cameraPaths.contains { $0.route == .boundarySurface })
    #expect(source.cameraLines.filter { $0.route == .boundarySurface }.count == 5)
    #expect(source.cameraPaths.allSatisfy { $0.route == .boundarySurface })
    #expect(interactionRecords.contains {
        guard case .affordance(let affordance) = $0.identity else { return false }
        return affordance.action == .boundarySurface(edgeTarget)
    })
}

@Test
func viewportBoundaryLoopIdentityRequiresExplicitCurveSamples() {
    let start = Point3D(x: 0, y: 0, z: 0)
    let end = Point3D(x: 1, y: 0, z: 0)
    let edge = ViewportBodyTopology.Edge(
        componentID: .bodyEdgeLeftBottom,
        start: start,
        end: end,
        openBoundaryLoopID: "loop"
    )

    #expect(edge.openBoundaryLoopID == nil)
}

@Test
func profileRoutesEmitNothingWhenTheirRouteIsNotInteractive() throws {
    let featureID = FeatureID()
    let nodeID = SceneNodeID()
    let item = profileBodyItem(
        featureID: featureID,
        nodeID: nodeID,
        topology: ViewportBodyTopology(
            edges: [
                .init(
                    componentID: .bodyEdgeLeftBottom,
                    start: Point3D(x: -1, y: 0, z: -1),
                    end: Point3D(x: 1, y: 0, z: -1)
                ),
            ]
        )
    )
    let cases: [(ProfileRoute, SelectionComponent)] = [
        (.profileCorner, .vertex(SelectionComponentID(rawValue: "body.vertex.0"))),
        (.profileFace, .face(.bodyFaceFront)),
        (.edgeFillet, .edge(.bodyEdgeLeftBottom)),
        (.profileEdgeChamfer, .edge(.bodyEdgeLeftBottom)),
    ]
    for (route, component) in cases {
        let target = SelectionTarget(sceneNodeID: nodeID, component: component)
        let raw = ProfileRawInput(
            document: .empty(),
            scene: ViewportScene(items: [item]),
            selection: SelectionModel(selectedTargets: [target]),
            ruler: .standard(for: .meter),
            enabledRoutes: [route],
            interactiveRoutes: []
        )
        var interactionRecords: [ViewportSpatialInteractionRecord] = []
        let source = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
        #expect(source == nil, "Route \(route.rawValue) must draw nothing while it is not interactive.")
        #expect(interactionRecords.isEmpty)
    }
}

@Test
func profileEdgeHandleRefusesAnEdgeSelectionBodyTopologyDoesNotBack() throws {
    let nodeID = SceneNodeID()
    let featureID = FeatureID()
    let item = profileBodyItem(featureID: featureID, nodeID: nodeID, topology: nil)
    let componentID = SelectionComponentID.generatedTopology(SubshapeID(featureID: featureID, role: "edge", ordinal: 0))
    let target = SelectionTarget(sceneNodeID: nodeID, component: .edge(componentID))
    let raw = profileRawInput(item: item, targets: [target], routes: [.edgeFillet])
    var interactionRecords: [ViewportSpatialInteractionRecord] = []
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try ViewportSpatialOverlayProducer.makeSurfaceTransformAffordanceSource(
            from: raw,
            interactionRecords: &interactionRecords,
            checkpoint: { _, _, _ in }
        )
    }
}

private func profileBodyItem(
    featureID: FeatureID,
    nodeID: SceneNodeID,
    topology: ViewportBodyTopology?
) -> ViewportSceneItem {
    ViewportSceneItem(
        id: "body",
        featureID: featureID,
        sceneNodeID: nodeID,
        modelBounds: CGRect(x: -1, y: -1, width: 2, height: 2),
        kind: .body(
            component: ViewportBodyComponent(
                sizeXMeters: 2,
                sizeYMeters: 1,
                sizeZMeters: 2,
                yMinMeters: 0,
                yMaxMeters: 1,
                topology: topology
            )
        )
    )
}

private func profileRawInput(
    item: ViewportSceneItem,
    targets: [SelectionTarget],
    routes: Set<ProfileRoute>
) -> ProfileRawInput {
    var document = DesignDocument.empty()
    document.cadDocument.designGraph = DesignGraph(
        nodes: [item.featureID: FeatureNode(
            id: item.featureID,
            operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
                width: .constant(.length(2, unit: .meter)),
                depth: .constant(.length(2, unit: .meter)),
                height: .constant(.length(1, unit: .meter))
            )))), outputs: [FeatureOutput(role: .body)]
        )], order: [item.featureID]
    )
    // Profile handles appear only on an unlocked object the document presents.
    if let nodeID = item.sceneNodeID {
        document.productMetadata.sceneNodes[nodeID] = SceneNode(id: nodeID, name: item.id, reference: .body(item.featureID))
        document.productMetadata.rootSceneNodeIDs.append(nodeID)
    }
    return ProfileRawInput(
        document: document,
        scene: ViewportScene(items: [item]),
        selection: SelectionModel(selectedTargets: targets),
        ruler: .standard(for: .meter),
        enabledRoutes: routes,
        interactiveRoutes: routes
    )
}

/// Collects the drawn overlay values one profile source produces.
private struct ProfileAffordanceOutput {
    var meshes: [ViewportSpatialOverlayInput.Mesh] = []
    var paths: [ViewportSpatialOverlayInput.Path] = []
    var labels: [ViewportSpatialOverlayInput.Label] = []
    var markers: [ViewportSpatialOverlayInput.Marker] = []
    var cameraLines: [ViewportSpatialOverlayInput.CameraLine] = []
    var cameraPaths: [ViewportSpatialOverlayInput.CameraPath] = []
    var activeFamilies: Set<ViewportSpatialOverlayFamily> = []

    mutating func append(
        from source: ViewportSpatialOverlayProducer.SurfaceTransformAffordanceSource,
        interactionRecords: inout [ViewportSpatialInteractionRecord]
    ) throws {
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
            activeFamilies: &activeFamilies
        )
    }
}
