import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene

public struct ViewportCameraFrame: Equatable, Sendable {
    public var target: Point3D
    public var visibleHeightMeters: Double
    public var camera: ViewportCamera

    public init(
        target: Point3D,
        visibleHeightMeters: Double,
        camera: ViewportCamera
    ) {
        self.target = target
        self.visibleHeightMeters = Self.normalizedVisibleHeightMeters(visibleHeightMeters)
        self.camera = camera
    }

    public static let minimumVisibleHeightMeters = 1.0e-12

    public static func normalizedVisibleHeightMeters(_ value: Double) -> Double {
        guard value.isFinite,
              value > minimumVisibleHeightMeters else {
            return minimumVisibleHeightMeters
        }
        return value
    }
}

public struct ViewportCameraFrameRequest: Equatable, Sendable {
    public var id: UUID
    public var target: Point3D
    public var visibleHeightMeters: Double
    public var basis: ViewportProjectionBasis

    public init(
        id: UUID = UUID(),
        target: Point3D,
        visibleHeightMeters: Double,
        basis: ViewportProjectionBasis
    ) {
        self.id = id
        self.target = target
        self.visibleHeightMeters = ViewportCameraFrame.normalizedVisibleHeightMeters(visibleHeightMeters)
        self.basis = basis
    }
}

public struct ViewportCameraFrameResolver: Sendable {
    public var workspaceVisibleSpanMeters: Double

    public init(workspaceVisibleSpanMeters: Double) {
        self.workspaceVisibleSpanMeters = ViewportCameraFrame.normalizedVisibleHeightMeters(
            workspaceVisibleSpanMeters
        )
    }

    public func camera(
        framing request: ViewportCameraFrameRequest,
        layoutForCamera: (ViewportCamera) -> ViewportLayout
    ) -> ViewportCamera {
        let identityLayout = layoutForCamera(.identity)
        let maximumZoom = identityLayout.maximumZoom
        let requestedZoom = CGFloat(workspaceVisibleSpanMeters / request.visibleHeightMeters)
        var nextCamera = ViewportCamera(zoom: requestedZoom).clamped(maximumZoom: maximumZoom)
        let projectedTarget = layoutForCamera(nextCamera).project(request.target)
        nextCamera.pan.width += identityLayout.fittingCenter.x - projectedTarget.x
        nextCamera.pan.height += identityLayout.fittingCenter.y - projectedTarget.y
        return nextCamera.clamped(maximumZoom: maximumZoom)
    }

    public func frame(
        for camera: ViewportCamera,
        in layout: ViewportLayout
    ) -> ViewportCameraFrame {
        let center = layout.unproject(layout.fittingCenter)
        let visibleHeightMeters = workspaceVisibleSpanMeters / Double(max(camera.zoom, ViewportCamera.minimumZoom))
        return ViewportCameraFrame(
            target: Point3D(
                x: Double(center.x),
                y: layout.renderOrigin.y,
                z: Double(center.y)
            ),
            visibleHeightMeters: visibleHeightMeters,
            camera: camera
        )
    }
}
