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

@Test
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
    let target = SelectionTarget(sceneNodeID: nodeID, component: .edge(.bodyEdgeLeftBottom))
    let raw = profileRawInput(
        item: item,
        targets: [target],
        routes: [.edgeFillet, .profileEdgeChamfer]
    )
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
    let anchor = Point3D(x: 0, y: 0, z: -1)
    let toward = edit.worldPoint(edit.centerPoint)
    let expected: [(ViewportAffordanceAction, CGFloat)] = [
        (.profileEdgeFillet(target, .leftBottom), ProfileMetrics.filletOffsetPoints),
        (.profileEdgeChamfer(target, .leftBottom), ProfileMetrics.chamferOffsetPoints),
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
            return affordance.action == .profileEdgeFillet(target, .leftBottom)
        }
    )
    let chamferIndex = try #require(
        interactionRecords.firstIndex {
            guard case .affordance(let affordance) = $0.identity else { return false }
            return affordance.action == .profileEdgeChamfer(target, .leftBottom)
        }
    )
    #expect(filletIndex < chamferIndex)
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
    let item = profileBodyItem(featureID: FeatureID(), nodeID: nodeID, topology: nil)
    let target = SelectionTarget(sceneNodeID: nodeID, component: .edge(.bodyEdgeLeftBottom))
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
    ProfileRawInput(
        document: .empty(),
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
