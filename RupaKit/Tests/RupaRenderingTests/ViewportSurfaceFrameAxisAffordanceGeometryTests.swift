import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportSurfaceFrameAxisAffordanceProjectsUDistance() throws {
    let layout = surfaceFrameAxisLayout()
    let display = surfaceFrameDisplay()
    let geometry = try #require(
        ViewportSurfaceFrameAxisAffordanceGeometry(
            display: display,
            axis: .u,
            modelTransform: .identity,
            layout: layout
        )
    )

    let start = layout.project(geometry.baseModelPoint)
    let current = layout.project(Point3D(x: 0.002, y: 0.0, z: 0.0))

    #expect(abs(geometry.dragDistance(start: start, current: current, layout: layout) - 0.002) < 1.0e-12)
}

@Test func viewportSurfaceFrameAxisAffordanceKeepsSignedVDistance() throws {
    let layout = surfaceFrameAxisLayout()
    let display = surfaceFrameDisplay()
    let geometry = try #require(
        ViewportSurfaceFrameAxisAffordanceGeometry(
            display: display,
            axis: .v,
            modelTransform: .identity,
            layout: layout
        )
    )

    let start = layout.project(geometry.baseModelPoint)
    let current = layout.project(Point3D(x: 0.0, y: 0.0, z: -0.0015))

    #expect(abs(geometry.dragDistance(start: start, current: current, layout: layout) + 0.0015) < 1.0e-12)
}

@Test func viewportSurfaceFrameAxisAffordanceProjectsNormalDistance() throws {
    let layout = surfaceFrameAxisLayout()
    let display = surfaceFrameDisplay()
    let geometry = try #require(
        ViewportSurfaceFrameAxisAffordanceGeometry(
            display: display,
            axis: .normal,
            modelTransform: .identity,
            layout: layout
        )
    )

    let start = layout.project(geometry.baseModelPoint)
    let current = layout.project(Point3D(x: 0.0, y: -0.003, z: 0.0))

    #expect(abs(geometry.dragDistance(start: start, current: current, layout: layout) - 0.003) < 1.0e-12)
}

@Test func viewportSurfaceFrameAxisAffordanceAppliesModelTransformAndKeepsLocalDistance() throws {
    let layout = surfaceFrameAxisLayout()
    let display = surfaceFrameDisplay()
    let modelTransform = try surfaceFrameAxisTransform(
        scale: 2.0,
        translationX: 0.006
    )
    let geometry = try #require(
        ViewportSurfaceFrameAxisAffordanceGeometry(
            display: display,
            axis: .u,
            modelTransform: modelTransform,
            layout: layout
        )
    )

    let start = layout.project(geometry.baseModelPoint)
    let current = layout.project(Point3D(x: 0.008, y: 0.0, z: 0.0))
    let tip = geometry.projectedTip(layout: layout, distanceMeters: 0.001)
    let expectedTip = layout.project(Point3D(x: 0.008, y: 0.0, z: 0.0))

    #expect(abs(geometry.baseModelPoint.x - 0.006) < 1.0e-12)
    #expect(abs(geometry.modelDirection.x - 2.0) < 1.0e-12)
    #expect(abs(geometry.dragDistance(start: start, current: current, layout: layout) - 0.001) < 1.0e-12)
    #expect(abs(tip.x - expectedTip.x) < 1.0e-9)
    #expect(abs(tip.y - expectedTip.y) < 1.0e-9)
}

private func surfaceFrameAxisLayout() -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: -0.004, y: -0.004, width: 0.014, height: 0.014),
        size: CGSize(width: 800.0, height: 600.0)
    )
}

private func surfaceFrameDisplay() -> ViewportSurfaceFrameDisplay {
    ViewportSurfaceFrameDisplay(
        id: SurfaceFrameDisplayID(rawValue: "test-surface-frame"),
        query: SurfaceFrameQuery(facePersistentName: "feature:test/generated:surface/subshape:face", u: 0.5, v: 0.5),
        position: Point3D(x: 0.0, y: 0.0, z: 0.0),
        uAxis: Vector3D(x: 1.0, y: 0.0, z: 0.0),
        vAxis: Vector3D(x: 0.0, y: 0.0, z: 1.0),
        normal: Vector3D(x: 0.0, y: -1.0, z: 0.0),
        u: 0.5,
        v: 0.5,
        facePersistentNames: []
    )
}

private func surfaceFrameAxisTransform(
    scale: Double,
    translationX: Double
) throws -> Transform3D {
    Transform3D(matrix: try Matrix4x4(values: [
        scale, 0.0, 0.0, 0.0,
        0.0, scale, 0.0, 0.0,
        0.0, 0.0, scale, 0.0,
        translationX, 0.0, 0.0, 1.0,
    ]))
}
