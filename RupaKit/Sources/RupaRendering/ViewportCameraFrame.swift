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
    public var projection: ViewportCameraProjection

    public init(
        id: UUID = UUID(),
        target: Point3D,
        visibleHeightMeters: Double,
        basis: ViewportProjectionBasis,
        projection: ViewportCameraProjection = .parallel
    ) {
        self.id = id
        self.target = target
        self.visibleHeightMeters = ViewportCameraFrame.normalizedVisibleHeightMeters(visibleHeightMeters)
        self.basis = basis
        self.projection = projection
    }
}

public enum ViewportCameraFrameError: Error, Equatable, Sendable {
    case invalidTarget
    case targetOutsideVisibleHalfSpace
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
    ) throws -> ViewportCamera {
        guard request.target.isFinite,
              request.visibleHeightMeters.isFinite,
              request.visibleHeightMeters > ViewportCameraFrame.minimumVisibleHeightMeters,
              request.projection.isValid else {
            throw ViewportCameraFrameError.invalidTarget
        }
        let identityLayout = layoutForCamera(.identity)
        let maximumZoom = identityLayout.maximumZoom
        let requestedZoom = CGFloat(identityLayout.visibleHeightMeters / request.visibleHeightMeters)
        let nextCamera = ViewportCamera(
            zoom: requestedZoom,
            projection: request.projection,
            focus: request.target
        ).clamped(maximumZoom: maximumZoom)
        let targetLayout = layoutForCamera(nextCamera)
        guard targetLayout.projectedPoint(request.target) != nil else {
            throw ViewportCameraFrameError.targetOutsideVisibleHalfSpace
        }
        return nextCamera.clamped(maximumZoom: maximumZoom)
    }

    public func frame(
        for camera: ViewportCamera,
        in layout: ViewportLayout
    ) -> ViewportCameraFrame? {
        guard let target = camera.pan == .zero
                ? layout.focus : layout.worldPointOnFocusPlane(for: layout.fittingCenter),
              target.isFinite else {
            return nil
        }
        let visibleHeightMeters = layout.visibleHeightMeters
        return ViewportCameraFrame(
            target: target,
            visibleHeightMeters: visibleHeightMeters,
            camera: camera
        )
    }
}
