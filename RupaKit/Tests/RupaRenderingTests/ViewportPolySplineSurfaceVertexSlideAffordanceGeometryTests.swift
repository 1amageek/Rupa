import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportPolySplineSurfaceVertexSlideAffordanceProjectsPositiveVDistance() throws {
    let layout = polySplineSurfaceVertexSlideLayout()
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let inputs = [
        try polySplineSurfaceVertexSlideInput(
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            role: .uMinVMin,
            point: Point3D(x: 0.0, y: 0.0, z: 0.0)
        )
    ]
    let topologyVertices = polySplineSurfaceVertexSlideTopologyVertices(featureID: featureID)
    let geometry = try #require(
        ViewportPolySplineSurfaceVertexSlideAffordanceGeometry(
            selectedVertices: inputs,
            topologyVertices: topologyVertices,
            direction: .positiveV,
            layout: layout
        )
    )

    let start = layout.project(geometry.baseModelPoint)
    let current = layout.project(Point3D(x: 0.0, y: 0.0, z: 0.002))

    #expect(abs(geometry.slideDistance(start: start, current: current, layout: layout) - 0.002) < 1.0e-12)
}

@Test func viewportPolySplineSurfaceVertexSlideAffordanceKeepsSignedNegativeUDistance() throws {
    let layout = polySplineSurfaceVertexSlideLayout()
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let inputs = [
        try polySplineSurfaceVertexSlideInput(
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            role: .uMaxVMin,
            point: Point3D(x: 0.004, y: 0.0, z: 0.0)
        )
    ]
    let topologyVertices = polySplineSurfaceVertexSlideTopologyVertices(featureID: featureID)
    let geometry = try #require(
        ViewportPolySplineSurfaceVertexSlideAffordanceGeometry(
            selectedVertices: inputs,
            topologyVertices: topologyVertices,
            direction: .negativeU,
            layout: layout
        )
    )

    let start = layout.project(geometry.baseModelPoint)
    let current = layout.project(Point3D(x: 0.005, y: 0.0, z: 0.0))

    #expect(abs(geometry.slideDistance(start: start, current: current, layout: layout) + 0.001) < 1.0e-12)
}

@Test func viewportPolySplineSurfaceVertexSlideAffordanceNormalUsesPatchHullCrossProduct() throws {
    let layout = polySplineSurfaceVertexSlideLayout()
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let inputs = [
        try polySplineSurfaceVertexSlideInput(
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            role: .uMinVMin,
            point: Point3D(x: 0.0, y: 0.0, z: 0.0)
        )
    ]
    let topologyVertices = polySplineSurfaceVertexSlideTopologyVertices(featureID: featureID)
    let geometry = try #require(
        ViewportPolySplineSurfaceVertexSlideAffordanceGeometry(
            selectedVertices: inputs,
            topologyVertices: topologyVertices,
            direction: .normal,
            layout: layout
        )
    )

    #expect(abs(geometry.modelDirection.x) < 1.0e-12)
    #expect(abs(geometry.modelDirection.y + 1.0) < 1.0e-12)
    #expect(abs(geometry.modelDirection.z) < 1.0e-12)
}

@Test func viewportPolySplineSurfaceVertexLocalDirectionUsesSharedPatchHullFrame() throws {
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let input = try polySplineSurfaceVertexSlideInput(
        featureID: featureID,
        sceneNodeID: sceneNodeID,
        role: .uMaxVMax,
        point: Point3D(x: 0.004, y: 0.0, z: 0.004)
    )
    let topologyVertices = polySplineSurfaceVertexSlideTopologyVertices(featureID: featureID)

    let positiveU = try #require(
        ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.localDirection(
            for: input.target,
            direction: .positiveU,
            topologyVertices: topologyVertices
        )
    )
    let positiveV = try #require(
        ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.localDirection(
            for: input.target,
            direction: .positiveV,
            topologyVertices: topologyVertices
        )
    )
    let normal = try #require(
        ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.localDirection(
            for: input.target,
            direction: .normal,
            topologyVertices: topologyVertices
        )
    )

    #expect(abs(positiveU.x - 1.0) < 1.0e-12)
    #expect(abs(positiveU.y) < 1.0e-12)
    #expect(abs(positiveU.z) < 1.0e-12)
    #expect(abs(positiveV.x) < 1.0e-12)
    #expect(abs(positiveV.y) < 1.0e-12)
    #expect(abs(positiveV.z - 1.0) < 1.0e-12)
    #expect(abs(normal.x) < 1.0e-12)
    #expect(abs(normal.y + 1.0) < 1.0e-12)
    #expect(abs(normal.z) < 1.0e-12)
}

@Test func viewportPolySplineSurfaceVertexSlideAffordanceRejectsIncompletePatchHull() throws {
    let layout = polySplineSurfaceVertexSlideLayout()
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let inputs = [
        try polySplineSurfaceVertexSlideInput(
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            role: .uMinVMin,
            point: Point3D(x: 0.0, y: 0.0, z: 0.0)
        )
    ]
    let topologyVertices = Array(polySplineSurfaceVertexSlideTopologyVertices(featureID: featureID).dropLast())

    let geometry = ViewportPolySplineSurfaceVertexSlideAffordanceGeometry(
        selectedVertices: inputs,
        topologyVertices: topologyVertices,
        direction: .positiveU,
        layout: layout
    )

    #expect(geometry == nil)
}

@Test func viewportPolySplineSurfaceVertexSlidePreviewMovesSelectedVerticesAlongLocalDirection() throws {
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let inputs = [
        try polySplineSurfaceVertexSlideInput(
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            role: .uMinVMin,
            point: Point3D(x: 0.000, y: 0.0, z: 0.000)
        ),
        try polySplineSurfaceVertexSlideInput(
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            role: .uMinVMax,
            point: Point3D(x: 0.000, y: 0.0, z: 0.004)
        ),
    ]
    let previewVertices = try #require(
        ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewVertices(
            selectedVertices: inputs,
            topologyVertices: polySplineSurfaceVertexSlideTopologyVertices(featureID: featureID),
            direction: .positiveU,
            distanceMeters: 0.001
        )
    )

    #expect(previewVertices.count == 2)
    #expect(abs(previewVertices[0].movedPoint.x - 0.001) < 1.0e-12)
    #expect(abs(previewVertices[0].movedPoint.z) < 1.0e-12)
    #expect(abs(previewVertices[1].movedPoint.x - 0.001) < 1.0e-12)
    #expect(abs(previewVertices[1].movedPoint.z - 0.004) < 1.0e-12)
}

@Test func viewportPolySplineSurfaceVertexSlidePreviewRegeneratesMovedSurfaceMesh() throws {
    let featureID = FeatureID()
    let sceneNodeID = SceneNodeID()
    let inputs = [
        try polySplineSurfaceVertexSlideInput(
            featureID: featureID,
            sceneNodeID: sceneNodeID,
            role: .uMinVMin,
            point: Point3D(x: 0.000, y: 0.0, z: 0.000)
        )
    ]
    let previewSurfaces = try #require(
        ViewportPolySplineSurfaceVertexSlideAffordanceGeometry.previewSurfaces(
            selectedVertices: inputs,
            topologyVertices: polySplineSurfaceVertexSlideTopologyVertices(featureID: featureID),
            direction: .positiveU,
            distanceMeters: 0.001,
            sampleSegmentCount: 2
        )
    )

    let surface = try #require(previewSurfaces.first)
    #expect(previewSurfaces.count == 1)
    #expect(surface.featureID == featureID)
    #expect(surface.patchID == 0)
    #expect(surface.originalMesh.positions.count == 9)
    #expect(surface.movedMesh.positions.count == 9)
    #expect(surface.movedMesh.indices.count == 24)
    #expect(abs(surface.originalMesh.positions[0].x) < 1.0e-12)
    #expect(abs(surface.movedMesh.positions[0].x - 0.001) < 1.0e-12)
    #expect(abs(surface.movedMesh.positions[0].z) < 1.0e-12)
    #expect(abs(surface.movedMesh.positions[2].x - 0.004) < 1.0e-12)
}

private func polySplineSurfaceVertexSlideLayout() -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: -0.002, y: -0.002, width: 0.010, height: 0.010),
        size: CGSize(width: 800.0, height: 600.0)
    )
}

private func polySplineSurfaceVertexSlideInput(
    featureID: FeatureID,
    sceneNodeID: SceneNodeID,
    role: PolySplineSurfaceVertexTarget.BoundaryRole,
    point: Point3D
) throws -> ViewportPolySplineSurfaceVertexSlideInput {
    let componentID = polySplineSurfaceVertexSlideComponentID(
        featureID: featureID,
        role: role
    )
    let target = try #require(PolySplineSurfaceVertexTarget.parse(componentID: componentID))
    return ViewportPolySplineSurfaceVertexSlideInput(
        target: target,
        selectionTarget: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .vertex(componentID)
        ),
        point: point
    )
}

private func polySplineSurfaceVertexSlideTopologyVertices(
    featureID: FeatureID
) -> [ViewportBodyTopology.Vertex] {
    [
        (.uMinVMin, Point3D(x: 0.000, y: 0.0, z: 0.000)),
        (.uMaxVMin, Point3D(x: 0.004, y: 0.0, z: 0.000)),
        (.uMaxVMax, Point3D(x: 0.004, y: 0.0, z: 0.004)),
        (.uMinVMax, Point3D(x: 0.000, y: 0.0, z: 0.004)),
    ].map { role, point in
        ViewportBodyTopology.Vertex(
            componentID: polySplineSurfaceVertexSlideComponentID(
                featureID: featureID,
                role: role
            ),
            point: point
        )
    }
}

private func polySplineSurfaceVertexSlideComponentID(
    featureID: FeatureID,
    role: PolySplineSurfaceVertexTarget.BoundaryRole
) -> SelectionComponentID {
    SelectionComponentID.generatedTopology(
        "feature:\(featureID.description)/generated:polySpline/subshape:patch:0:vertex:\(role.rawValue)"
    )
}
