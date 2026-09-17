import CoreGraphics
import Foundation
import Observation
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaViewportScene

/// Identifies one mounted viewport instance inside a document/window session.
public struct ViewportInstanceID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Captures one concrete SwiftUI mount of a viewport.
///
/// A layout transition can overlap the departing view's `onDisappear` with
/// the replacement view's `onAppear`. The token keeps the departing callback
/// from unmounting a replacement that uses the same viewport instance ID.
public struct ViewportMountToken: Hashable, Sendable {
    public let viewportID: ViewportInstanceID
    private let rawValue: UUID

    fileprivate init(viewportID: ViewportInstanceID) {
        self.viewportID = viewportID
        self.rawValue = UUID()
    }
}

public enum ViewportOrientation: String, CaseIterable, Codable, Equatable, Sendable {
    case isometric
    case xFront
    case yFront
    case zFront

    var projectionBasis: ViewportProjectionBasis {
        switch self {
        case .isometric:
            .isometric
        case .xFront:
            .axisFront(.x)
        case .yFront:
            .axisFront(.y)
        case .zFront:
            .axisFront(.z)
        }
    }
}

public enum ViewportControlAction: Equatable, Sendable {
    case fitVisible
    case fitSelected
    case orbit(yawDeltaDegrees: Double, elevationDeltaDegrees: Double)
    case pan(deltaXPoints: Double, deltaYPoints: Double)
    case zoom(factor: Double, anchor: CGPoint? = nil)
    case setOrientation(ViewportOrientation)
    case setProjection(ViewportCameraProjection)
    case resetCamera
    case setDisplayMode(ViewportDisplayMode)
    case setShading(ViewportShading)
}

public enum ViewportControlError: Error, Equatable, LocalizedError, Sendable {
    case viewportNotMounted
    case viewportContextUnavailable
    case revisionMismatch(expected: UInt64, actual: UInt64)
    case emptyVisibleBounds
    case emptySelectedBounds
    case nonFiniteBounds
    case invalidViewportSize
    case nonFiniteInput
    case invalidZoomFactor
    case invalidProjection
    case fitWouldExceedCameraLimits
    case invalidShading(ViewportShadingError)

    public var errorDescription: String? {
        switch self {
        case .viewportNotMounted:
            "The viewport session is not mounted."
        case .viewportContextUnavailable:
            "The mounted viewport has not supplied a geometry context."
        case .revisionMismatch(let expected, let actual):
            "Viewport revision mismatch: expected \(expected), current revision is \(actual)."
        case .emptyVisibleBounds:
            "The viewport has no visible geometry to fit."
        case .emptySelectedBounds:
            "The viewport has no visible selected geometry to fit."
        case .nonFiniteBounds:
            "Viewport geometry bounds contain a non-finite coordinate."
        case .invalidViewportSize:
            "The viewport size is not large enough for a camera operation."
        case .nonFiniteInput:
            "Viewport operation input must be finite."
        case .invalidZoomFactor:
            "Viewport zoom factor must be finite and greater than zero."
        case .invalidProjection:
            "Viewport camera projection parameters are invalid."
        case .fitWouldExceedCameraLimits:
            "The requested fit cannot be contained within the camera limits."
        case .invalidShading(let error):
            error.errorDescription
        }
    }
}

public struct ViewportControlSnapshot: Equatable, Sendable {
    public let id: ViewportInstanceID
    public let revision: UInt64
    public let basis: ViewportProjectionBasis
    public let camera: ViewportCamera
    public let viewportSize: CGSize
    public let canFitVisible: Bool
    public let canFitSelected: Bool
    public let displayMode: ViewportDisplayMode
    public let shading: ViewportShading

    public init(
        id: ViewportInstanceID,
        revision: UInt64,
        basis: ViewportProjectionBasis,
        camera: ViewportCamera,
        viewportSize: CGSize,
        canFitVisible: Bool,
        canFitSelected: Bool,
        displayMode: ViewportDisplayMode,
        shading: ViewportShading = .standard
    ) {
        self.id = id
        self.revision = revision
        self.basis = basis
        self.camera = camera
        self.viewportSize = viewportSize
        self.canFitVisible = canFitVisible
        self.canFitSelected = canFitSelected
        self.displayMode = displayMode
        self.shading = shading
    }
}

/// Main-actor owner for one document/window viewport lifetime.
///
/// The session is the only mutable camera, display-mode, and ephemeral-shading
/// authority shared by SwiftUI gestures and the Agent adapter. It contains no
/// project or source authority. A viewport must attach its current layout
/// context before a command can be executed.
@MainActor
@Observable
public final class ViewportControlSession {
    public let id: ViewportInstanceID

    public private(set) var camera: ViewportCamera
    public private(set) var basis: ViewportProjectionBasis
    public private(set) var displayMode: ViewportDisplayMode
    public private(set) var shading: ViewportShading
    public private(set) var revision: UInt64
    public private(set) var isMounted = false

    public var isReady: Bool { isMounted && context != nil }
    public var canFitVisible: Bool { isReady && context?.sceneBounds != nil }
    public var canFitSelected: Bool { isReady && context?.selectedBounds != nil }

    private(set) var orbitBasis: ViewportProjectionBasis?
    private(set) var selectedAxis: ViewportCoordinateAxis?
    private(set) var projectionTransition: ViewportProjectionTransition?
    private var mountedMountToken: ViewportMountToken?
    private var context: ViewportControlMountContext?

    public init(
        id: ViewportInstanceID = ViewportInstanceID(),
        camera: ViewportCamera = .identity,
        basis: ViewportProjectionBasis = .isometric,
        displayMode: ViewportDisplayMode = .solid,
        shading: ViewportShading = .standard
    ) {
        self.id = id
        self.camera = camera
        self.basis = basis
        self.displayMode = displayMode
        self.shading = shading
        self.revision = 0
    }

    @discardableResult
    public func mount(viewportID: ViewportInstanceID) -> ViewportMountToken {
        let token = ViewportMountToken(viewportID: viewportID)
        context = nil
        revision = revision &+ 1
        mountedMountToken = token
        isMounted = true
        return token
    }

    /// Unmounts only the concrete mount that owns the callback.
    public func unmount(_ token: ViewportMountToken) {
        guard mountedMountToken == token else {
            return
        }
        mountedMountToken = nil
        context = nil
        isMounted = false
        revision = revision &+ 1
    }

    /// Returns a snapshot only after a mounted viewport has supplied geometry.
    public func snapshot() throws -> ViewportControlSnapshot {
        try makeSnapshot()
    }

    @discardableResult
    public func perform(
        _ action: ViewportControlAction,
        expectedRevision: UInt64? = nil
    ) throws -> ViewportControlSnapshot {
        guard expectedRevision == nil || expectedRevision == revision else {
            throw ViewportControlError.revisionMismatch(
                expected: expectedRevision ?? revision,
                actual: revision
            )
        }
        guard isMounted else {
            throw ViewportControlError.viewportNotMounted
        }
        guard let context else {
            throw ViewportControlError.viewportContextUnavailable
        }
        try validateContext(context)

        var nextCamera = try centeredCamera(camera, basis: basis, context: context)
        var nextBasis = basis
        var nextOrbitBasis = orbitBasis
        var nextSelectedAxis = selectedAxis
        var nextTransition = projectionTransition
        var nextDisplayMode = displayMode
        var nextShading = shading

        switch action {
        case .fitVisible:
            guard context.sceneBounds != nil else {
                throw ViewportControlError.emptyVisibleBounds
            }
            nextCamera = try ViewportControlBoundsSolver.camera(
                for: context.sceneBounds,
                sceneModelBounds: context.modelBounds,
                verticalBounds: context.verticalBounds,
                basis: basis,
                size: context.viewportSize,
                fittingInsets: context.fittingInsets,
                maximumZoom: context.maximumZoom(for: basis),
                projection: camera.projection
            )
        case .fitSelected:
            guard context.selectedBounds != nil else {
                throw ViewportControlError.emptySelectedBounds
            }
            nextCamera = try ViewportControlBoundsSolver.camera(
                for: context.selectedBounds,
                sceneModelBounds: context.modelBounds,
                verticalBounds: context.verticalBounds,
                basis: basis,
                size: context.viewportSize,
                fittingInsets: context.fittingInsets,
                maximumZoom: context.maximumZoom(for: basis),
                projection: camera.projection
            )
        case .orbit(let yawDeltaDegrees, let elevationDeltaDegrees):
            guard yawDeltaDegrees.isFinite, elevationDeltaDegrees.isFinite else {
                throw ViewportControlError.nonFiniteInput
            }
            let current = currentProjectionBasis(at: Date())
            let yawDeltaRadians = yawDeltaDegrees * .pi / 180.0
            let elevationDeltaRadians = elevationDeltaDegrees * .pi / 180.0
            let yaw = Double(current.orbitYawRadians) + yawDeltaRadians
            let elevation = Double(current.orbitElevationRadians) + elevationDeltaRadians
            guard yaw.isFinite, elevation.isFinite else {
                throw ViewportControlError.nonFiniteInput
            }
            nextBasis = .orbit(yaw: CGFloat(yaw), elevation: CGFloat(elevation))
            nextCamera = preservingScale(nextCamera, from: current, to: nextBasis, context: context)
            nextOrbitBasis = nextBasis
            nextSelectedAxis = nil
            nextTransition = nil
        case .pan(let deltaXPoints, let deltaYPoints):
            guard deltaXPoints.isFinite, deltaYPoints.isFinite else {
                throw ViewportControlError.nonFiniteInput
            }
            let nextPanX = Double(nextCamera.pan.width) + deltaXPoints
            let nextPanY = Double(nextCamera.pan.height) + deltaYPoints
            guard nextPanX.isFinite, nextPanY.isFinite else {
                throw ViewportControlError.nonFiniteInput
            }
            nextCamera.pan = CGSize(
                width: CGFloat(nextPanX),
                height: CGFloat(nextPanY)
            )
            nextCamera = try centeredCamera(nextCamera, basis: nextBasis, context: context)
        case .zoom(let factor, let anchor):
            guard factor.isFinite, factor > 0.0 else {
                throw ViewportControlError.invalidZoomFactor
            }
            let factorAsCGFloat = CGFloat(factor)
            guard factorAsCGFloat.isFinite else {
                throw ViewportControlError.nonFiniteInput
            }
            let anchorWorld: Point3D?
            if let anchor {
                guard anchor.x.isFinite, anchor.y.isFinite,
                      let world = layout(camera: nextCamera, basis: nextBasis, context: context)
                        .worldPointOnFocusPlane(for: anchor) else {
                    throw ViewportControlError.nonFiniteInput
                }
                anchorWorld = world
            } else {
                anchorWorld = nil
            }
            let zoom = nextCamera.zoom * factorAsCGFloat
            guard zoom.isFinite else {
                throw ViewportControlError.nonFiniteInput
            }
            nextCamera.zoom = zoom
            nextCamera = nextCamera.clamped(maximumZoom: context.maximumZoom(for: nextBasis, camera: nextCamera))
            if let anchor, let anchorWorld {
                guard let projected = layout(camera: nextCamera, basis: nextBasis, context: context)
                    .projectedPoint(anchorWorld)?.point else {
                    throw ViewportControlError.nonFiniteInput
                }
                nextCamera.pan = CGSize(width: anchor.x - projected.x, height: anchor.y - projected.y)
                nextCamera = try centeredCamera(nextCamera, basis: nextBasis, context: context)
            }
        case .setOrientation(let orientation):
            nextBasis = orientation.projectionBasis
            nextCamera = preservingScale(nextCamera, from: basis, to: nextBasis, context: context)
            nextOrbitBasis = nil
            nextSelectedAxis = orientation.selectedAxis
            nextTransition = nil
        case .setProjection(let projection):
            guard projection.isValid else {
                throw ViewportControlError.invalidProjection
            }
            nextCamera.projection = projection
        case .resetCamera:
            nextCamera = ViewportCamera(
                zoom: 1.0,
                pan: .zero,
                projection: camera.projection
            )
            nextCamera = try centeredCamera(nextCamera, basis: nextBasis, context: context)
        case .setDisplayMode(let mode):
            nextDisplayMode = mode
        case .setShading(let next):
            do {
                try next.validate()
            } catch let error as ViewportShadingError {
                throw ViewportControlError.invalidShading(error)
            }
            nextShading = next
        }

        guard nextCamera.zoom.isFinite,
              nextCamera.pan.width.isFinite,
              nextCamera.pan.height.isFinite,
              nextCamera.projection.isValid,
              nextCamera.focus?.isFinite == true,
              nextBasis.xDirection.dx.isFinite,
              nextBasis.xDirection.dy.isFinite,
              nextBasis.yDirection.dx.isFinite,
              nextBasis.yDirection.dy.isFinite,
              nextBasis.zDirection.dx.isFinite,
              nextBasis.zDirection.dy.isFinite else {
            throw ViewportControlError.nonFiniteInput
        }
        nextCamera = try centeredCamera(nextCamera, basis: nextBasis, context: context)
        nextCamera = nextCamera.clamped(maximumZoom: context.maximumZoom(for: nextBasis, camera: nextCamera))
        try validateProjection(camera: nextCamera, basis: nextBasis, context: context)

        let changed = nextCamera != camera
            || nextBasis != basis
            || nextOrbitBasis != orbitBasis
            || nextSelectedAxis != selectedAxis
            || nextTransition != projectionTransition
            || nextDisplayMode != displayMode
            || nextShading != shading
        guard changed else {
            return try makeSnapshot()
        }

        camera = nextCamera
        basis = nextBasis
        orbitBasis = nextOrbitBasis
        selectedAxis = nextSelectedAxis
        projectionTransition = nextTransition
        displayMode = nextDisplayMode
        shading = nextShading
        revision = revision &+ 1
        return try makeSnapshot()
    }

    /// Attaches the layout and visible bounds used by fit commands.
    ///
    /// This is intentionally internal: only the mounted `Viewport` can supply
    /// a valid source-scene context, while the App sees the throwing public
    /// snapshot/perform boundary.
    func updateContext(_ context: ViewportControlMountContext) {
        guard isMounted, mountedMountToken?.viewportID == context.viewportID else {
            return
        }
        guard self.context != context else {
            return
        }
        self.context = context
        camera = camera.clamped(maximumZoom: context.maximumZoom(for: basis, camera: camera))
        if camera.focus == nil || camera.referenceScale == nil {
            let initialLayout = layout(camera: camera, basis: basis, context: context)
            if let focus = initialLayout.worldPointOnFocusPlane(for: initialLayout.fittingCenter), focus.isFinite {
                camera.focus = focus
                camera.referenceScale = initialLayout.scale / camera.zoom
                camera.pan = .zero
            }
        }
        revision = revision &+ 1
    }

    /// Applies a presentation request produced by the existing saved-view
    /// path. It remains behind the same session owner and revision boundary as
    /// interactive and Agent camera mutations.
    func applyPresentationState(
        camera nextCamera: ViewportCamera,
        basis nextBasis: ViewportProjectionBasis
    ) throws {
        guard isMounted else {
            throw ViewportControlError.viewportNotMounted
        }
        guard let context else {
            throw ViewportControlError.viewportContextUnavailable
        }
        guard nextCamera.zoom.isFinite,
              nextCamera.zoom > 0,
              nextCamera.projection.isValid,
              nextCamera.pan.width.isFinite,
              nextCamera.pan.height.isFinite,
              nextBasis.xDirection.dx.isFinite, nextBasis.xDirection.dy.isFinite,
              nextBasis.yDirection.dx.isFinite, nextBasis.yDirection.dy.isFinite,
              nextBasis.zDirection.dx.isFinite, nextBasis.zDirection.dy.isFinite else {
            throw ViewportControlError.nonFiniteInput
        }
        let nextCamera = try centeredCamera(
            nextCamera.clamped(maximumZoom: context.maximumZoom(for: nextBasis, camera: nextCamera)),
            basis: nextBasis, context: context
        )
        try validateProjection(camera: nextCamera, basis: nextBasis, context: context)
        guard nextCamera != camera || nextBasis != basis else { return }
        camera = nextCamera
        basis = nextBasis
        orbitBasis = nextBasis.mode == .orbit ? nextBasis : nil
        switch nextBasis.mode {
        case .axisFront(let axis): selectedAxis = axis
        case .isometric, .orbit: selectedAxis = nil
        }
        projectionTransition = nil
        revision = revision &+ 1
    }

    func setProjectionTransition(
        _ transition: ViewportProjectionTransition?,
        basis nextBasis: ViewportProjectionBasis,
        orbitBasis nextOrbitBasis: ViewportProjectionBasis?,
        selectedAxis nextSelectedAxis: ViewportCoordinateAxis?
    ) {
        guard nextBasis != basis
            || transition != projectionTransition
            || nextOrbitBasis != orbitBasis
            || nextSelectedAxis != selectedAxis else {
            return
        }
        if let context {
            camera = preservingScale(camera, from: basis, to: nextBasis, context: context)
        }
        basis = nextBasis
        projectionTransition = transition
        orbitBasis = nextOrbitBasis
        selectedAxis = nextSelectedAxis
        revision = revision &+ 1
    }

    private func currentProjectionBasis(at date: Date) -> ViewportProjectionBasis {
        if let projectionTransition {
            return projectionTransition.basis(at: date)
        }
        if let orbitBasis {
            return orbitBasis
        }
        return basis
    }

    private func makeSnapshot() throws -> ViewportControlSnapshot {
        guard isMounted else {
            throw ViewportControlError.viewportNotMounted
        }
        guard let context else {
            throw ViewportControlError.viewportContextUnavailable
        }
        try validateContext(context)
        return ViewportControlSnapshot(
            id: id,
            revision: revision,
            basis: basis,
            camera: camera,
            viewportSize: context.viewportSize,
            canFitVisible: context.sceneBounds != nil,
            canFitSelected: context.selectedBounds != nil,
            displayMode: displayMode,
            shading: shading
        )
    }

    private func validateContext(_ context: ViewportControlMountContext) throws {
        guard context.viewportSize.width.isFinite, context.viewportSize.height.isFinite,
              context.viewportSize.width > 0, context.viewportSize.height > 0 else {
            throw ViewportControlError.invalidViewportSize
        }
    }

    private func layout(
        camera: ViewportCamera, basis: ViewportProjectionBasis,
        context: ViewportControlMountContext
    ) -> ViewportLayout {
        ViewportLayout(
            modelBounds: context.modelBounds, size: context.viewportSize,
            camera: camera, basis: basis, maximumZoom: context.maximumZoom(for: basis, camera: camera),
            verticalBounds: context.verticalBounds, fittingInsets: context.fittingInsets
        )
    }

    private func centeredCamera(
        _ camera: ViewportCamera, basis: ViewportProjectionBasis,
        context: ViewportControlMountContext
    ) throws -> ViewportCamera {
        guard camera.focus?.isFinite != false,
              camera.referenceScale.map({ $0.isFinite && $0 > 0 }) != false else {
            throw ViewportControlError.nonFiniteInput
        }
        let layout = layout(camera: camera, basis: basis, context: context)
        guard let focus = layout.worldPointOnFocusPlane(for: layout.fittingCenter), focus.isFinite else {
            throw ViewportControlError.nonFiniteInput
        }
        var result = camera
        result.focus = camera.pan == .zero ? layout.focus : focus
        result.referenceScale = camera.referenceScale ?? layout.scale / camera.zoom
        result.pan = .zero
        return result
    }

    private func preservingScale(
        _ camera: ViewportCamera, from oldBasis: ViewportProjectionBasis,
        to newBasis: ViewportProjectionBasis, context: ViewportControlMountContext
    ) -> ViewportCamera {
        let oldLayout = layout(camera: camera, basis: oldBasis, context: context)
        let newLayout = layout(camera: camera, basis: newBasis, context: context)
        var result = camera
        result.zoom *= oldLayout.scale / newLayout.scale
        return result.clamped(maximumZoom: context.maximumZoom(for: newBasis, camera: result))
    }

    private func validateProjection(
        camera: ViewportCamera, basis: ViewportProjectionBasis,
        context: ViewportControlMountContext
    ) throws {
        let layout = ViewportLayout(
            modelBounds: context.modelBounds, size: context.viewportSize,
            camera: camera, basis: basis, maximumZoom: context.maximumZoom(for: basis, camera: camera),
            verticalBounds: context.verticalBounds, fittingInsets: context.fittingInsets
        )
        // The shared camera must remain representable by the Metal clip uniforms.
        guard let rows = layout.projectionRows(relativeTo: Point3D.origin),
              rows.isFinite,
              [rows.x.x, rows.x.y, rows.x.z, rows.x.constant,
               rows.y.x, rows.y.y, rows.y.z, rows.y.constant,
               rows.depth.x, rows.depth.y, rows.depth.z, rows.depth.constant,
               rows.w.x, rows.w.y, rows.w.z, rows.w.constant]
                .allSatisfy({ Float($0).isFinite }) else {
            throw ViewportControlError.nonFiniteInput
        }
    }
}

struct ViewportControlMountContext: Equatable {
    let viewportID: ViewportInstanceID
    let viewportSize: CGSize
    let fittingInsets: ViewportLayout.FittingInsets
    let modelBounds: CGRect
    let verticalBounds: ClosedRange<Double>?
    let ruler: RulerConfiguration
    let sceneBounds: GeometryBounds3D?
    let selectedBounds: GeometryBounds3D?

    func maximumZoom(for basis: ViewportProjectionBasis, camera: ViewportCamera = .identity) -> CGFloat {
        let identityLayout = ViewportLayout(
            modelBounds: modelBounds, size: viewportSize, basis: basis,
            verticalBounds: verticalBounds, fittingInsets: fittingInsets
        )
        return ViewportCameraZoomPolicy.maximumZoom(ruler: ruler, identityScale: camera.referenceScale ?? identityLayout.scale)
    }
}

struct ViewportControlBoundsSolver {
    static func camera(
        for bounds: GeometryBounds3D?,
        sceneModelBounds: CGRect,
        verticalBounds: ClosedRange<Double>?,
        basis: ViewportProjectionBasis,
        size: CGSize,
        fittingInsets: ViewportLayout.FittingInsets,
        maximumZoom: CGFloat,
        projection: ViewportCameraProjection = .parallel
    ) throws -> ViewportCamera {
        guard let bounds else {
            throw ViewportControlError.emptyVisibleBounds
        }
        guard size.width.isFinite, size.height.isFinite,
              size.width > 1.0, size.height > 1.0 else {
            throw ViewportControlError.invalidViewportSize
        }
        guard bounds.minimum.x.isFinite, bounds.minimum.y.isFinite,
              bounds.minimum.z.isFinite, bounds.maximum.x.isFinite,
              bounds.maximum.y.isFinite, bounds.maximum.z.isFinite,
              bounds.minimum.x <= bounds.maximum.x,
              bounds.minimum.y <= bounds.maximum.y,
              bounds.minimum.z <= bounds.maximum.z else {
            throw ViewportControlError.nonFiniteBounds
        }
        guard sceneModelBounds.origin.x.isFinite,
              sceneModelBounds.origin.y.isFinite,
              sceneModelBounds.width.isFinite,
              sceneModelBounds.height.isFinite,
              sceneModelBounds.width > 0.0,
              sceneModelBounds.height > 0.0 else {
            throw ViewportControlError.invalidViewportSize
        }
        guard projection.isValid else {
            throw ViewportControlError.invalidProjection
        }

        if projection != .parallel {
            return try perspectiveCamera(
                for: bounds,
                sceneModelBounds: sceneModelBounds,
                verticalBounds: verticalBounds,
                basis: basis,
                size: size,
                fittingInsets: fittingInsets,
                projection: projection,
                maximumZoom: maximumZoom
            )
        }

        let fittingRect = fittingInsets.fittingRect(in: size)
        let focus = center(of: bounds)
        let identityLayout = ViewportLayout(
            modelBounds: sceneModelBounds,
            size: size,
            camera: ViewportCamera(projection: projection, focus: focus),
            basis: basis,
            maximumZoom: maximumZoom,
            verticalBounds: verticalBounds,
            fittingInsets: fittingInsets
        )
        guard identityLayout.scale.isFinite, identityLayout.scale > 0.0 else {
            throw ViewportControlError.invalidViewportSize
        }

        var minimumX = CGFloat.infinity
        var minimumY = CGFloat.infinity
        var maximumX = -CGFloat.infinity
        var maximumY = -CGFloat.infinity
        for corner in corners(of: bounds) {
            let projected = identityLayout.project(corner)
            guard projected.x.isFinite, projected.y.isFinite else {
                throw ViewportControlError.nonFiniteBounds
            }
            minimumX = min(minimumX, projected.x)
            minimumY = min(minimumY, projected.y)
            maximumX = max(maximumX, projected.x)
            maximumY = max(maximumY, projected.y)
        }

        let projectedWidth = maximumX - minimumX
        let projectedHeight = maximumY - minimumY
        guard projectedWidth.isFinite, projectedHeight.isFinite,
              projectedWidth >= 0.0, projectedHeight >= 0.0 else {
            throw ViewportControlError.nonFiniteBounds
        }
        let effectiveWidth = max(projectedWidth, 1.0e-9)
        let effectiveHeight = max(projectedHeight, 1.0e-9)
        let widthFactor = fittingRect.width / effectiveWidth
        let heightFactor = fittingRect.height / effectiveHeight
        let requestedZoom = min(widthFactor, heightFactor)
        guard requestedZoom.isFinite, requestedZoom > 0.0 else {
            throw ViewportControlError.nonFiniteInput
        }
        guard requestedZoom >= ViewportCamera.minimumZoom else {
            throw ViewportControlError.fitWouldExceedCameraLimits
        }

        return ViewportCamera(
            zoom: requestedZoom,
            pan: .zero,
            projection: projection,
            focus: focus
        ).clamped(maximumZoom: maximumZoom)
    }

    private static func perspectiveCamera(
        for bounds: GeometryBounds3D,
        sceneModelBounds: CGRect,
        verticalBounds: ClosedRange<Double>?,
        basis: ViewportProjectionBasis,
        size: CGSize,
        fittingInsets: ViewportLayout.FittingInsets,
        projection: ViewportCameraProjection,
        maximumZoom: CGFloat
    ) throws -> ViewportCamera {
        let fittingRect = fittingInsets.fittingRect(in: size)
        let minimumZoom = ViewportCamera.minimumZoom
        let resolvedMaximumZoom = max(maximumZoom, minimumZoom)
        let focus = center(of: bounds)

        func projectedBounds(for zoom: CGFloat) -> CGRect? {
            let camera = ViewportCamera(zoom: zoom, projection: projection, focus: focus)
            let layout = ViewportLayout(
                modelBounds: sceneModelBounds,
                size: size,
                camera: camera,
                basis: basis,
                maximumZoom: resolvedMaximumZoom,
                verticalBounds: verticalBounds,
                fittingInsets: fittingInsets
            )
            var minX = CGFloat.infinity
            var minY = CGFloat.infinity
            var maxX = -CGFloat.infinity
            var maxY = -CGFloat.infinity
            for corner in corners(of: bounds) {
                guard let projected = layout.projectedPoint(corner) else {
                    return nil
                }
                minX = min(minX, projected.point.x)
                minY = min(minY, projected.point.y)
                maxX = max(maxX, projected.point.x)
                maxY = max(maxY, projected.point.y)
            }
            let result = CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
            guard result.origin.x.isFinite, result.origin.y.isFinite,
                  result.width.isFinite, result.height.isFinite else {
                return nil
            }
            return result
        }

        func fits(_ zoom: CGFloat) -> CGRect? {
            guard let projected = projectedBounds(for: zoom),
                  projected.minX >= fittingRect.minX - 1.0e-6,
                  projected.maxX <= fittingRect.maxX + 1.0e-6,
                  projected.minY >= fittingRect.minY - 1.0e-6,
                  projected.maxY <= fittingRect.maxY + 1.0e-6 else {
                return nil
            }
            return projected
        }

        guard fits(minimumZoom) != nil else {
            throw ViewportControlError.fitWouldExceedCameraLimits
        }
        var bestZoom = minimumZoom
        if fits(resolvedMaximumZoom) != nil {
            bestZoom = resolvedMaximumZoom
        } else {
            var lower = minimumZoom
            var upper = resolvedMaximumZoom
            for _ in 0..<32 {
                let candidate = (lower + upper) * 0.5
                if fits(candidate) != nil {
                    lower = candidate
                    bestZoom = candidate
                } else {
                    upper = candidate
                }
            }
        }

        let camera = ViewportCamera(
            zoom: bestZoom,
            pan: .zero,
            projection: projection,
            focus: focus
        ).clamped(maximumZoom: resolvedMaximumZoom)
        let finalLayout = ViewportLayout(
            modelBounds: sceneModelBounds,
            size: size,
            camera: camera,
            basis: basis,
            maximumZoom: resolvedMaximumZoom,
            verticalBounds: verticalBounds,
            fittingInsets: fittingInsets
        )
        guard let finalBounds = projectedBounds(for: camera.zoom),
              finalBounds.minX + camera.pan.width >= fittingRect.minX - 1.0e-4,
              finalBounds.maxX + camera.pan.width <= fittingRect.maxX + 1.0e-4,
              finalBounds.minY + camera.pan.height >= fittingRect.minY - 1.0e-4,
              finalBounds.maxY + camera.pan.height <= fittingRect.maxY + 1.0e-4,
              finalLayout.projectionRows(relativeTo: Point3D.origin)?.isFinite == true else {
            throw ViewportControlError.fitWouldExceedCameraLimits
        }
        return camera
    }

    private static func center(of bounds: GeometryBounds3D) -> Point3D {
        Point3D(
            x: bounds.minimum.x * 0.5 + bounds.maximum.x * 0.5,
            y: bounds.minimum.y * 0.5 + bounds.maximum.y * 0.5,
            z: bounds.minimum.z * 0.5 + bounds.maximum.z * 0.5
        )
    }

    private static func corners(of bounds: GeometryBounds3D) -> [Point3D] {
        (0..<8).map { index in
            Point3D(
                x: index & 1 == 0 ? bounds.minimum.x : bounds.maximum.x,
                y: index & 2 == 0 ? bounds.minimum.y : bounds.maximum.y,
                z: index & 4 == 0 ? bounds.minimum.z : bounds.maximum.z
            )
        }
    }
}

private extension ViewportOrientation {
    var selectedAxis: ViewportCoordinateAxis? {
        switch self {
        case .isometric:
            nil
        case .xFront:
            .x
        case .yFront:
            .y
        case .zFront:
            .z
        }
    }
}
