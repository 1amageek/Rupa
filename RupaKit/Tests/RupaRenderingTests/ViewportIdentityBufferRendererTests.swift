import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportIdentityBufferRendererSamplesGeneratedTopologyHits() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let buffer = try renderer.render(plan: plan, viewportSize: viewportSize)
    let faceSample = try buffer.sample(
        at: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0))
    )
    let vertexSample = try buffer.sample(
        at: layout.project(Point3D(x: -0.020, y: 0.0, z: -0.020))
    )
    let backgroundSample = try buffer.sample(at: CGPoint(x: 4.0, y: 4.0))

    #expect(faceSample.rawValue != ViewportPickIdentity.backgroundRawValue)
    #expect(faceSample.hit?.pickingBackend == .identityBuffer)
    #expect(faceSample.hit?.selectionComponent == .face(faceComponentID))
    #expect(vertexSample.hit?.selectionComponent == .vertex(vertexComponentID))
    #expect(backgroundSample.rawValue == ViewportPickIdentity.backgroundRawValue)
    #expect(backgroundSample.identity == nil)
    #expect(backgroundSample.hit == nil)
}

@MainActor
@Test func viewportIdentityHitResolverReturnsIdentityBufferGeneratedTopologyHit() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )

    let hit = resolver.hitTest(
        point: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0)),
        in: scene,
        layout: layout
    )

    #expect(hit?.pickingBackend == .identityBuffer)
    #expect(hit?.selectionComponent == .face(faceComponentID))
}

@MainActor
@Test func viewportIdentityHitResolverFallsBackToProjectedCPUWhenRendererIsUnavailable() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver(rendererFactory: {
        throw ViewportIdentityBufferRendererError.deviceUnavailable
    })
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )

    let hit = resolver.hitTest(
        point: layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0)),
        in: scene,
        layout: layout
    )

    #expect(hit?.pickingBackend == .projectedCPU)
    #expect(hit?.selectionComponent == .face(faceComponentID))
}

@Test func viewportIdentityBufferReturnsSelectionHitsInsideRectangle() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let buffer = try renderer.render(plan: plan, viewportSize: viewportSize)
    let hits = buffer.hits(
        in: CGRect(
            x: 0.0,
            y: 0.0,
            width: viewportSize.width,
            height: viewportSize.height
        )
    )

    #expect(hits.contains {
        $0.pickingBackend == .identityBuffer && $0.selectionComponent == .face(faceComponentID)
    })
    #expect(hits.contains {
        $0.pickingBackend == .identityBuffer && $0.selectionComponent == .edge(edgeComponentID)
    })
    #expect(hits.contains {
        $0.pickingBackend == .identityBuffer && $0.selectionComponent == .vertex(vertexComponentID)
    })
}

@MainActor
@Test func viewportIdentityHitResolverReturnsIdentityBufferSelectionHits() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver()
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let hits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout
    )

    #expect(hits.contains { $0.pickingBackend == .identityBuffer })
    #expect(hits.contains { $0.selectionComponent == .vertex(vertexComponentID) })
}

@MainActor
@Test func viewportIdentityHitResolverSelectionFallsBackToProjectedCPUWhenRendererIsUnavailable() throws {
    let scene = identityBufferGeneratedTopologyScene()
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver(rendererFactory: {
        throw ViewportIdentityBufferRendererError.deviceUnavailable
    })
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )

    let hits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout
    )

    #expect(hits.contains { $0.pickingBackend == .projectedCPU })
    #expect(hits.contains { $0.selectionComponent == .vertex(vertexComponentID) })
}

@MainActor
@Test func viewportIdentityHitResolverSelectionHonorsSketchControlPointPolicy() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Viewport Identity Rectangle Spline Policy",
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
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let resolver = ViewportIdentityHitResolver()

    let hiddenHits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout,
        sketchControlPointHitPolicy: .none
    )
    let visibleHits = resolver.selectionHits(
        in: CGRect(x: 0.0, y: 0.0, width: viewportSize.width, height: viewportSize.height),
        scene: scene,
        layout: layout,
        sketchControlPointHitPolicy: .all
    )

    #expect(hiddenHits.contains { $0.sketchControlPointIndex != nil } == false)
    #expect(visibleHits.contains { $0.sketchControlPointIndex == 1 })
}

@MainActor
@Test func viewportIdentityBufferRendererSamplesProjectedBodyFallbackHits() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let scene = ViewportSceneBuilder().build(document: session.document)
    let viewportSize = CGSize(width: 240.0, height: 180.0)
    let layout = try #require(ViewportLayout(scene: scene, size: viewportSize))
    let bodyItem = try #require(scene.items.first { item in
        if case .body = item.kind {
            return true
        }
        return false
    })
    let projection = try #require(layout.bodyProjection(for: bodyItem))
    let plan = ViewportIdentityPickRenderPlanBuilder().build(scene: scene, layout: layout)
    let renderer = try ViewportIdentityBufferRenderer()

    let vertexSample = try renderer.sample(
        point: projection.point(for: .backTopRight),
        plan: plan,
        viewportSize: viewportSize
    )

    #expect(vertexSample.rawValue != ViewportPickIdentity.backgroundRawValue)
    #expect(vertexSample.hit?.pickingBackend == .identityBuffer)
    #expect(vertexSample.hit?.bodyVertex == .backTopRight)
}

private func identityBufferGeneratedTopologyScene() -> ViewportScene {
    let featureID = FeatureID()
    let faceComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:face:front"
    )
    let edgeComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:edge:frontBottom"
    )
    let vertexComponentID = SelectionComponentID.generatedTopology(
        "feature:body:subshape:identity:vertex:frontBottomLeft"
    )
    let frontBottomLeft = Point3D(x: -0.020, y: 0.0, z: -0.020)
    let frontBottomRight = Point3D(x: 0.020, y: 0.0, z: -0.020)
    let frontTopRight = Point3D(x: 0.020, y: 0.0, z: 0.020)
    let frontTopLeft = Point3D(x: -0.020, y: 0.0, z: 0.020)
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
        sizeXMeters: 0.040,
        sizeYMeters: 0.020,
        sizeZMeters: 0.040,
        yMinMeters: 0.0,
        yMaxMeters: 0.020,
        topology: topology
    )
    let item = ViewportSceneItem(
        id: featureID.description,
        featureID: featureID,
        modelBounds: CGRect(x: -0.020, y: -0.020, width: 0.040, height: 0.040),
        kind: .body(component: component)
    )
    return ViewportScene(items: [item])
}
