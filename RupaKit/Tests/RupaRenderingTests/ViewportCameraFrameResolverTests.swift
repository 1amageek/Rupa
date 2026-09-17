import CoreGraphics
import RupaCore
import RupaRendering
import Testing

@Test func viewportCameraFrameResolverCentersRequestedTargetAndRestoresVisibleHeight() throws {
    let viewportSize = CGSize(width: 900.0, height: 700.0)
    let modelBounds = CGRect(x: -10.0, y: -10.0, width: 20.0, height: 20.0)
    let fittingInsets = ViewportLayout.FittingInsets(
        top: 40.0,
        leading: 70.0,
        bottom: 60.0,
        trailing: 20.0
    )
    let basis = ViewportProjectionBasis.orbit(yaw: 0.35, elevation: 0.45)
    let target = Point3D(x: 4.0, y: 3.0, z: -2.0)
    let request = ViewportCameraFrameRequest(
        target: target,
        visibleHeightMeters: 5.0,
        basis: basis
    )
    let resolver = ViewportCameraFrameResolver(workspaceVisibleSpanMeters: 20.0)

    let camera = try resolver.camera(framing: request) { camera in
        ViewportLayout(
            modelBounds: modelBounds,
            size: viewportSize,
            camera: camera,
            basis: basis,
            maximumZoom: 32.0,
            fittingInsets: fittingInsets
        )
    }
    let layout = ViewportLayout(
        modelBounds: modelBounds,
        size: viewportSize,
        camera: camera,
        basis: basis,
        maximumZoom: 32.0,
        fittingInsets: fittingInsets
    )
    let projectedTarget = try #require(layout.projectedPoint(target)?.point)

    #expect(abs(layout.visibleHeightMeters - request.visibleHeightMeters) < 1.0e-9)
    #expect(abs(projectedTarget.x - layout.viewportCenter.x) < 1.0e-6)
    #expect(abs(projectedTarget.y - layout.viewportCenter.y) < 1.0e-6)
    #expect(camera.focus == target)
    #expect(try #require(resolver.frame(for: camera, in: layout)).target == target)
}

@Test func viewportCameraFramePreservesElevatedFocusInBothLenses() throws {
    let target = Point3D(x: 17, y: 9, z: -6)
    let resolver = ViewportCameraFrameResolver(workspaceVisibleSpanMeters: 20)
    for projection in [ViewportCameraProjection.parallel, .standardPerspective] {
        func layout(_ camera: ViewportCamera) -> ViewportLayout {
            ViewportLayout(modelBounds: CGRect(x: -10, y: -10, width: 20, height: 20),
                size: CGSize(width: 900, height: 700), camera: camera,
                basis: .orbit(yaw: 0.8, elevation: 0.4), verticalBounds: -2...2)
        }
        let request = ViewportCameraFrameRequest(target: target, visibleHeightMeters: 4,
            basis: .orbit(yaw: 0.8, elevation: 0.4), projection: projection)
        let camera = try resolver.camera(framing: request, layoutForCamera: layout)
        let frame = try #require(resolver.frame(for: camera, in: layout(camera)))
        #expect(frame.target == target)
        #expect(abs(frame.visibleHeightMeters - 4) < 1e-8)
        let point = CGPoint(x: 220, y: 170)
        let world = try #require(layout(camera).worldPointOnFocusPlane(for: point))
        let roundTrip = layout(camera).project(world)
        #expect(hypot(point.x - roundTrip.x, point.y - roundTrip.y) < 1e-7)
    }
}

@Test func viewportCameraFrameResolverCapturesCurrentFrameFromCameraPanAndZoom() throws {
    let viewportSize = CGSize(width: 900.0, height: 700.0)
    let modelBounds = CGRect(x: -10.0, y: -10.0, width: 20.0, height: 20.0)
    let fittingInsets = ViewportLayout.FittingInsets(
        top: 36.0,
        leading: 80.0,
        bottom: 64.0,
        trailing: 24.0
    )
    let camera = ViewportCamera(
        zoom: 2.5,
        pan: CGSize(width: -120.0, height: 80.0)
    )
    let layout = ViewportLayout(
        modelBounds: modelBounds,
        size: viewportSize,
        camera: camera,
        basis: .isometric,
        maximumZoom: 32.0,
        fittingInsets: fittingInsets
    )
    let resolver = ViewportCameraFrameResolver(workspaceVisibleSpanMeters: 20.0)

    let frame = try #require(resolver.frame(for: camera, in: layout))
    let projectedTarget = try #require(layout.projectedPoint(frame.target)?.point)

    #expect(frame.camera == camera)
    #expect(abs(frame.visibleHeightMeters - layout.visibleHeightMeters) < 1.0e-9)
    #expect(abs(projectedTarget.x - layout.viewportCenter.x) < 1.0e-6)
    #expect(abs(projectedTarget.y - layout.viewportCenter.y) < 1.0e-6)
    #expect(abs(projectedTarget.x - layout.fittingCenter.x) > 1.0)
    #expect(abs(projectedTarget.y - layout.fittingCenter.y) > 1.0)
}
