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
