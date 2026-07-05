import CoreGraphics
import RupaCore
import RupaRendering
import Testing

@Test func viewportCameraFrameResolverCentersRequestedTargetAndRestoresZoom() {
    let viewportSize = CGSize(width: 900.0, height: 700.0)
    let modelBounds = CGRect(x: -10.0, y: -10.0, width: 20.0, height: 20.0)
    let basis = ViewportProjectionBasis.orbit(yaw: 0.35, elevation: 0.45)
    let target = Point3D(x: 4.0, y: 3.0, z: -2.0)
    let request = ViewportCameraFrameRequest(
        target: target,
        visibleHeightMeters: 5.0,
        basis: basis
    )
    let resolver = ViewportCameraFrameResolver(workspaceVisibleSpanMeters: 20.0)

    let camera = resolver.camera(framing: request) { camera in
        ViewportLayout(
            modelBounds: modelBounds,
            size: viewportSize,
            camera: camera,
            basis: basis,
            maximumZoom: 32.0
        )
    }
    let layout = ViewportLayout(
        modelBounds: modelBounds,
        size: viewportSize,
        camera: camera,
        basis: basis,
        maximumZoom: 32.0
    )
    let projectedTarget = layout.project(target)

    #expect(abs(camera.zoom - 4.0) < 1.0e-9)
    #expect(abs(projectedTarget.x - viewportSize.width / 2.0) < 1.0e-6)
    #expect(abs(projectedTarget.y - viewportSize.height / 2.0) < 1.0e-6)
}

@Test func viewportCameraFrameResolverCapturesCurrentFrameFromCameraPanAndZoom() {
    let viewportSize = CGSize(width: 900.0, height: 700.0)
    let modelBounds = CGRect(x: -10.0, y: -10.0, width: 20.0, height: 20.0)
    let camera = ViewportCamera(
        zoom: 2.5,
        pan: CGSize(width: -120.0, height: 80.0)
    )
    let layout = ViewportLayout(
        modelBounds: modelBounds,
        size: viewportSize,
        camera: camera,
        basis: .isometric,
        maximumZoom: 32.0
    )
    let resolver = ViewportCameraFrameResolver(workspaceVisibleSpanMeters: 20.0)

    let frame = resolver.frame(for: camera, in: layout)
    let projectedTarget = layout.project(frame.target)

    #expect(frame.camera == camera)
    #expect(abs(frame.visibleHeightMeters - 8.0) < 1.0e-9)
    #expect(abs(projectedTarget.x - viewportSize.width / 2.0) < 1.0e-6)
    #expect(abs(projectedTarget.y - viewportSize.height / 2.0) < 1.0e-6)
}
