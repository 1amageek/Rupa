import CoreGraphics
import RupaCore

/// Answers `ViewportNativeFrameProbe` from the frame `MeshSourcePresentationPlanCache`
/// has mounted for one preparation identity at one camera revision.
///
/// The identity and the revision are fixed when the probe is made, so every
/// question a resolver asks through it reaches the same mounted frame. A frame
/// that is not ready, belongs to another snapshot, or has moved past the
/// revision is reported by the cache as a typed failure, and this type adds no
/// rule of its own on top of that: it holds the query authority steady and
/// forwards.
@MainActor
struct ViewportNativePresentationFrameProbe {
    private let planCache: MeshSourcePresentationPlanCache
    private let identity: RealityViewportPreparationRequest.Identity
    private let revision: UInt64

    /// The projection the mounted frame was drawn with, resolved once here.
    ///
    /// Making the probe therefore asks the frame one question. The callers that
    /// make one already asked it unconditionally, so the query the frame sees is
    /// unchanged, and the per-pixel edge walk no longer repeats it.
    let usesPerspectiveProjection: Bool

    init(
        planCache: MeshSourcePresentationPlanCache,
        identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws {
        self.planCache = planCache
        self.identity = identity
        self.revision = revision
        self.usesPerspectiveProjection = try planCache.usesPerspectiveProjection(
            for: identity, revision: revision
        )
    }

    func projectedPointWithinDepthRange(
        _ point: Point3D
    ) throws -> (point: CGPoint, depth: Double)? {
        try planCache.projectedPointWithinDepthRange(point, for: identity, revision: revision)
    }

    func projectedPointWithDepth(
        _ point: Point3D
    ) throws -> (point: CGPoint?, depth: Double) {
        try planCache.projectedPointWithDepth(point, for: identity, revision: revision)
    }

    func retainsSectionedPoint(_ point: Point3D) throws -> Bool {
        try planCache.retainsSectionedPoint(point, for: identity, revision: revision)
    }

    func surfaceHit(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        try planCache.surfaceHit(at: point, for: identity, revision: revision)
    }

    func regionFragment(
        at point: CGPoint
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)? {
        try planCache.regionFragment(at: point, for: identity, revision: revision)
    }

    func cameraDepthInterval() throws -> ClosedRange<Double> {
        try planCache.cameraDepthInterval(for: identity, revision: revision)
    }

    func sectionParameterBound(
        from start: Point3D,
        to end: Point3D
    ) throws -> ViewportCameraDepthClip.AffineScalarBound? {
        try planCache.sectionParameterBound(
            from: start, to: end, for: identity, revision: revision
        )
    }

    func regionSegmentProbe(
        from start: CGPoint,
        to end: CGPoint,
        within rect: CGRect,
        startingAt step: Int
    ) throws -> RealityViewportRegionSegmentProbe {
        try planCache.regionSegmentProbe(
            from: start, to: end, within: rect,
            startingAt: step, for: identity, revision: revision
        )
    }
}

// The plan cache is main-actor isolated, so the conformance is too. The probe
// protocol stays non-isolated: the resolvers that consume it are pure functions
// of the answers, and a test double answers them off the main actor.
extension ViewportNativePresentationFrameProbe: @MainActor ViewportNativeFrameProbe {}
