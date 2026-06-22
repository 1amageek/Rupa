import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func viewportSceneBuilderCreatesSelectableSketchAndBodyItems() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

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
    #expect(scene.modelBounds != nil)
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
    #expect(item.continuity == .g1)
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
    #expect(overlay.items.first?.continuity == .g1)
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
        profiles: [ProfileReference(featureID: profileID)],
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
        profiles: [ProfileReference(featureID: profileID)],
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
        profiles: [ProfileReference(featureID: profileID)],
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
        profiles: [ProfileReference(featureID: profileID)],
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
    let edgeHitTarget = try #require(generatedEdgeHitTarget(in: topology, scene: scene, layout: layout))
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
        layout: layout
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
    _ = try #require(session.createDefaultExtrudedRectangle())
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
        allowsSketchControlPointHit: { _, _ in false }
    )
    let visibleControlPointHits = ViewportSelectionRectangleHitTester().hits(
        in: selectionRect,
        scene: scene,
        layout: layout,
        allowsSketchControlPointHit: { _, _ in true }
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
        component: fixture.vertexComponent,
        point: hitPoint,
        layout: layout
    )
    let edgeHit = ViewportBodyTopologyHitTester().hitTest(
        component: fixture.edgeComponent,
        point: hitPoint,
        layout: layout
    )
    let faceHit = ViewportBodyTopologyHitTester(tolerance: 0.0).hitTest(
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
        sketchPlane: .yz
    )

    let constrained = drag.constrained(by: .z)

    #expect(constrained.start == drag.start)
    #expect(abs(constrained.end.x - 0.01) < 1.0e-12)
    #expect(abs(constrained.end.y - 0.03) < 1.0e-12)
    #expect(constrained.sketchPlane == .yz)
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

@Test func viewportProjectedGridCreatesCoordinateParallelLines() {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.millimeter)
    let grid = ViewportProjectedGrid(
        document: document,
        size: CGSize(width: 800.0, height: 600.0)
    )
    let xLines = grid.lines(for: .x)
    let zLines = grid.lines(for: .z)
    let firstXVector = vector(for: xLines[0])
    let firstZVector = vector(for: zLines[0])

    #expect(!xLines.isEmpty)
    #expect(!zLines.isEmpty)
    #expect(xLines.contains { $0.isMajor })
    #expect(zLines.contains { $0.isMajor })
    #expect(grid.majorStepMeters >= document.ruler.majorTickMeters)
    #expect(grid.minorStepMeters >= document.ruler.minorTickMeters)
    #expect(abs(firstXVector.dx) > 0.0)
    #expect(abs(firstXVector.dy) > 0.0)
    #expect(abs(firstZVector.dx) > 0.0)
    #expect(abs(firstZVector.dy) > 0.0)
    #expect(firstXVector.dx * firstZVector.dx < 0.0)
    #expect(!isParallel(firstXVector, firstZVector))
    #expect(xLines.prefix(12).allSatisfy { isParallel(vector(for: $0), firstXVector) })
    #expect(zLines.prefix(12).allSatisfy { isParallel(vector(for: $0), firstZVector) })
}

private func vector(for line: ViewportProjectedGrid.Line) -> CGVector {
    CGVector(
        dx: line.end.x - line.start.x,
        dy: line.end.y - line.start.y
    )
}

private func isParallel(_ lhs: CGVector, _ rhs: CGVector) -> Bool {
    let crossProduct = lhs.dx * rhs.dy - lhs.dy * rhs.dx
    let scale = max(hypot(lhs.dx, lhs.dy) * hypot(rhs.dx, rhs.dy), 1.0)
    return abs(crossProduct / scale) < 1.0e-9
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
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )
    let session = EditorSession(document: document)
    let result = try session.execute(.createSweep(
        name: "Viewport Curved Sweep",
        profiles: [ProfileReference(featureID: profileID)],
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
    layout: ViewportLayout
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
            let hit = tester.hitTest(point: projectedPoint, in: scene, layout: layout)
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

private struct OverlappingGeneratedFaceScene {
    var scene: ViewportScene
    var nearCenter: Point3D
    var nearFeatureID: FeatureID
    var nearFaceComponentID: SelectionComponentID
}

private struct OverlappingGeneratedPrimitiveComponent {
    var modelBounds: CGRect
    var nearCenter: Point3D
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
    basis: ViewportProjectionBasis
) -> CGRect {
    let points = [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: basis.xDirection.dx * width, y: basis.xDirection.dy * width),
        CGPoint(x: basis.zDirection.dx * height, y: basis.zDirection.dy * height),
        CGPoint(
            x: basis.xDirection.dx * width + basis.zDirection.dx * height,
            y: basis.xDirection.dy * width + basis.zDirection.dy * height
        ),
    ]
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
