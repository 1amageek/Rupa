import Foundation
import Observation
import RupaCoreTypes
import RupaGeometry
import RupaViewportScene
import SwiftCAD

/// Prepares one complete native frame off-scene and publishes only matching output.
///
/// The cache owns exactly one build at a time. Preparing a different scene
/// retains the running worker within the same display context and keeps only
/// the newest pending request. Completed frames advance display without giving
/// stale snapshots query authority. Context replacement and teardown cancel the
/// worker and invalidate its publication token; GPU builds never overlap.
@Observable
@MainActor
final class MeshSourcePresentationPlanCache {
    /// Builds a plan for one scene. Injected so a test can decide when a build
    /// completes without depending on construction timing.
    typealias Builder = @Sendable (UniversalViewportScene) async throws -> MeshSourcePresentationRenderPlan

    private(set) var state: MeshSourcePresentationPlanState = .idle

    @ObservationIgnored private let builder: Builder
    @ObservationIgnored private var buildTask: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var pendingRequest: (request: RealityViewportPreparationRequest, id: UUID)?
    private var current: Prepared?

    init(
        builder: @escaping Builder = { scene in
            try MeshSourcePresentationRenderPlan(scene: scene)
        }
    ) {
        self.builder = builder
    }

    deinit { buildTask?.cancel() }

    /// The plan for `scene`, or `nil` while the cache is idle, preparing, or
    /// holding a result that belongs to a different scene identity.
    func plan(for scene: UniversalViewportScene) -> MeshSourcePresentationRenderPlan? {
        guard case let .ready(identity, plan, _) = state,
              identity.snapshotID == scene.snapshotID else {
            return nil
        }
        return plan
    }

    func surface(for identity: RealityViewportPreparationRequest.Identity) -> RealityViewport? {
        guard case let .ready(current, _, surface) = state,
              current == identity else { return nil }
        return surface
    }

    func hasReadyCamera(for identity: RealityViewportPreparationRequest.Identity, revision: UInt64) -> Bool {
        queryAuthority(for: identity)?.isCameraReady(revision: revision) == true
    }

    /// The frame a query for `identity` resolves against.
    ///
    /// A pointer can only have addressed pixels that were drawn, so the frame
    /// the view mounted answers for it. That is the exact-ready frame once this
    /// identity is prepared, and otherwise the mounted frame the display is
    /// still showing for the same scene and snapshot, whose ordered handle
    /// indexes name its own prepared record table. A recorded failure for this
    /// identity keeps the display but withdraws its authority, and a changed
    /// scene or snapshot withdraws both.
    private func queryAuthority(for identity: RealityViewportPreparationRequest.Identity) -> RealityViewport? {
        switch state {
        case let .ready(current, _, surface) where current == identity:
            return surface
        case let .failed(current, _) where current == identity:
            return nil
        default:
            return displaySurface(for: identity)
        }
    }

    /// Queries the frame mounted for `identity`, never a frame drawn for a
    /// different scene or snapshot.
    func surfaceHit(
        at point: CGPoint,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        try querySurface(for: identity).surfaceHit(at: point, revision: revision)
    }

    /// Answers the selection rectangle from the frame mounted for `identity`,
    /// never a frame drawn for a different scene or snapshot. The result is the
    /// answering frame's own plan order.
    func occurrenceIDs(
        intersecting rect: CGRect,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> [SceneOccurrenceID] {
        try querySurface(for: identity).occurrenceIDs(intersecting: rect, revision: revision)
    }

    /// Emits the triangles the frame mounted for `identity` draws inside
    /// `rect`, never a frame drawn for a different scene or snapshot.
    ///
    /// The rectangle is answered from the frame's own per-pixel visibility
    /// rather than from samples of it, so the answer holds every triangle the
    /// frame shows there and nothing it hides.
    func forEachRegionTriangle(
        intersecting rect: CGRect,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64,
        _ body: (MeshSourcePresentationTriangle) throws -> Void
    ) throws {
        try querySurface(for: identity).forEachRegionTriangle(
            intersecting: rect, revision: revision, body
        )
    }

    /// The triangle the frame mounted for `identity` draws at one point, and
    /// the depth it draws it at. A nil result is the frame drawing nothing
    /// there, which is what an occlusion test reads as an unoccluded pixel.
    func regionFragment(
        at point: CGPoint,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> (triangle: MeshSourcePresentationTriangle, depth: Double)? {
        try querySurface(for: identity).regionFragment(
            at: point, revision: revision
        )
    }

    /// Walks a projected segment across the mounted frame's own device pixels
    /// and reports the first drawn one at or after `step`, so a consumer
    /// rejecting a pixel resumes the walk rather than restarting it.
    func regionSegmentProbe(
        from start: CGPoint,
        to end: CGPoint,
        within rect: CGRect,
        startingAt step: Int,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> RealityViewportRegionSegmentProbe {
        try querySurface(for: identity).regionSegmentProbe(
            from: start, to: end, within: rect,
            startingAt: step, revision: revision
        )
    }

    /// Resolves the native priority order the mounted frame drew.
    func interactionRecords(
        at point: CGPoint,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> [ViewportSpatialInteractionRecord] {
        let surface = try querySurface(for: identity)
        let indices = try surface.spatialHandleHits(at: point, revision: revision)
        return try indices.map { index in
            guard let record = interactionRecord(at: index, for: identity) else {
                throw queryFailure("The native handle has no matching prepared interaction record.")
            }
            return record
        }
    }

    /// Materialization must revalidate both identities for every projected point.
    func project(
        _ point: Point3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> CGPoint {
        try querySurface(for: identity).project(point, revision: revision)
    }

    func projectWithinDepthRange(
        _ point: Point3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> CGPoint {
        try querySurface(for: identity).projectWithinDepthRange(point, revision: revision)
    }

    /// Reports the mounted camera's own depth interval so a selection rectangle
    /// can clip candidate geometry against it in world space instead of
    /// discarding a triangle whose vertices straddle a clip plane.
    func cameraDepthInterval(
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> ClosedRange<Double> {
        try querySurface(for: identity).cameraDepthInterval(revision: revision)
    }

    /// Reports a world point's camera-space depth, and its projected point
    /// wherever the mounted camera answers for one. Depth is reported whether
    /// or not `cameraDepthInterval(for:revision:)` admits it, because the
    /// crossing of a clip plane is interpolated from the depths on both sides.
    func projectedPointWithDepth(
        _ point: Point3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> (point: CGPoint?, depth: Double) {
        try querySurface(for: identity).projectedPointWithDepth(point, revision: revision)
    }

    /// Admits a world point and reports its camera-space depth so callers can
    /// compare candidate depths against the native surface frame. A nil result
    /// is a valid depth rejection, never a silent projection failure.
    func projectedPointWithinDepthRange(
        _ point: Point3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> (point: CGPoint, depth: Double)? {
        try querySurface(for: identity).projectedPointWithinDepthRange(point, revision: revision)
    }

    /// Reports the projection the mounted frame was drawn with, so depth
    /// interpolation along a projected segment follows the mounted camera
    /// instead of being inferred from the sampled depths.
    func usesPerspectiveProjection(
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> Bool {
        try querySurface(for: identity).usesPerspectiveProjection(revision: revision)
    }

    /// Reports whether the mounted frame retains a world point through the
    /// active section. A removed point draws nothing, exactly like a silhouette
    /// point, so this is the only query that separates the two.
    func retainsSectionedPoint(
        _ point: Point3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> Bool {
        try querySurface(for: identity).retainsSectionedPoint(point, revision: revision)
    }

    /// Reports the active section's signed distance at the ends of a world
    /// segment as one affine bound, or nil when the frame has no section. The
    /// region rectangle's edge rule narrows a segment against this bound once
    /// instead of asking the point predicate per sample.
    func sectionParameterBound(
        from start: Point3D,
        to end: Point3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> ViewportCameraDepthClip.AffineScalarBound? {
        try querySurface(for: identity).sectionParameterBound(
            from: start, to: end, revision: revision
        )
    }

    /// Resolves a world plane through the exact-ready native camera owned by
    /// `identity`. The cache validates preparation identity before any native
    /// query so retained display surfaces cannot acquire input authority.
    func worldPlaneIntersection(
        at point: CGPoint,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> Point3D {
        try querySurface(for: identity).worldPlaneIntersection(
            at: point, planeOrigin: planeOrigin, planeNormal: planeNormal, revision: revision
        )
    }

    /// Resolves the plane through `anchor` perpendicular to the direction the
    /// mounted frame is looking along. The frame states that direction from
    /// the camera entity it installed, so a caller never names a view plane
    /// the frame did not draw.
    func viewPlaneIntersection(
        at point: CGPoint,
        through anchor: Point3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> Point3D {
        try querySurface(for: identity).viewPlaneIntersection(
            at: point, through: anchor, revision: revision
        )
    }

    func worldAxisParameter(
        at point: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> Double {
        try querySurface(for: identity).worldAxisParameter(
            at: point, axisOrigin: axisOrigin, axisDirection: axisDirection, revision: revision
        )
    }

    func worldAxisDelta(
        from start: CGPoint,
        to end: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> Double {
        try querySurface(for: identity).worldAxisDelta(
            from: start, to: end, axisOrigin: axisOrigin, axisDirection: axisDirection, revision: revision
        )
    }

    private func querySurface(for identity: RealityViewportPreparationRequest.Identity) throws -> RealityViewport {
        if case let .failed(current, error) = state, current == identity { throw error }
        if let surface = queryAuthority(for: identity) { return surface }
        // No frame has judged this identity: nothing is prepared, a preparation
        // is in flight, or the state belongs to another scene or snapshot and
        // the display has not caught up. A failure recorded for this identity
        // is answered above and is never one of these.
        switch state {
        case .idle:
            throw notReadyFailure("The native surface query is unavailable before preparation.")
        case .preparing:
            throw notReadyFailure("The native surface query is unavailable while preparation is in progress.")
        case .ready:
            throw notReadyFailure("The native surface query uses a stale preparation identity.")
        case .failed:
            throw notReadyFailure("The native surface query uses a stale failed preparation identity.")
        }
    }

    func meshElement(
        at point: CGPoint,
        domain: GeometryAttributeDomain,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> ViewportMeshElementHit? {
        let surface = try querySurface(for: identity)
        let pointerHit = try surface.surfaceHit(at: point, revision: revision)
        guard let current, current.surface === surface, let plan = current.plan else { return nil }
        return try MeshSourcePresentationMeshElementResolver.resolve(
            at: point, domain: domain, in: plan,
            project: { try self.project($0, for: identity, revision: revision) },
            surfaceHit: { candidate in
                if candidate == point { return pointerHit?.triangle }
                return try self.surfaceHit(at: candidate, for: identity, revision: revision)?.triangle
            }
        )
    }


    /// The complete frame retained through an overlay-only replacement.
    ///
    /// Display and queries share this rule so the two cannot disagree about
    /// which frame the viewport is showing. Only the overlay revision may
    /// differ; a changed scene or snapshot withdraws it.
    func displaySurface(for identity: RealityViewportPreparationRequest.Identity) -> RealityViewport? {
        guard let requested = state.identity,
              requested.scene == identity.scene, requested.snapshotID == identity.snapshotID,
              let current, current.identity.scene == identity.scene,
              current.identity.snapshotID == identity.snapshotID else { return nil }
        return current.surface
    }

    /// A completed picture, not an input authority. The newest request may still
    /// be preparing; its scene/snapshot queries must continue to use displaySurface.
    func displayCandidate(for identity: RealityViewportPreparationRequest.Identity) -> RealityViewport? {
        guard state.identity == identity, let current,
              current.identity.sharesDisplayContext(with: identity) else { return nil }
        return current.surface
    }

    func interactionRecord(at index: UInt32, for identity: RealityViewportPreparationRequest.Identity) -> ViewportSpatialInteractionRecord? {
        guard let surface = queryAuthority(for: identity),
              let current, current.surface === surface,
              Int(index) < current.interactionRecords.count else { return nil }
        return current.interactionRecords[Int(index)]
    }

    /// Every prepared interaction record of the frame that answers for `identity`.
    ///
    /// Overlays that mark where the frame drew a native handle enumerate the
    /// records under the same guard `interactionRecord(at:for:)` uses, so an
    /// enumeration and an index lookup can never name different frames. The
    /// caller decides readiness with `hasReadyCamera(for:revision:)` before
    /// projecting anything; a throw here means no frame answers at all.
    func interactionRecords(
        for identity: RealityViewportPreparationRequest.Identity
    ) throws -> [ViewportSpatialInteractionRecord] {
        let surface = try querySurface(for: identity)
        guard let current, current.surface === surface else {
            throw notReadyFailure(
                "The native interaction records are unavailable before the prepared frame is retained."
            )
        }
        return current.interactionRecords
    }

    /// The failure recorded for this identity, or `nil` when the current state is not
    /// a failure that belongs to this scene identity.
    func failure(for identity: RealityViewportPreparationRequest.Identity) -> MeshSourcePresentationRenderError? {
        guard case let .failed(current, error) = state,
              current == identity else {
            return nil
        }
        return error
    }

    /// Whether a build for this scene identity is still in flight.
    func isPreparing(_ identity: RealityViewportPreparationRequest.Identity) -> Bool {
        guard case let .preparing(current) = state else {
            return false
        }
        return current == identity
    }

    /// Starts a build unless the cache already describes that complete frame
    /// identity. Must not be called from a SwiftUI `body`: it publishes
    /// `preparing` synchronously and mutating observable state during a view
    /// update is undefined behavior.
    func prepare(_ request: RealityViewportPreparationRequest) {
        guard state.identity != request.identity else {
            return
        }
        if state.identity?.sharesDisplayContext(with: request.identity) != true {
            buildTask?.cancel()
            self.requestID = nil
        }
        let requestID = UUID()
        if displaySurface(for: request.identity) == nil {
            current?.surface.invalidateCamera()
            // The old frame may remain a picture, but cannot answer queries
            // for the newly requested scene or snapshot.
        }
        state = .preparing(identity: request.identity)
        if buildTask != nil {
            pendingRequest = (request, requestID)
        } else {
            start(request, requestID: requestID)
        }
    }

    /// Captures the source-owned overlay builder synchronously on the caller's
    /// actor, then submits the complete request only while that task remains
    /// live.  A cancelled view task cannot prepare or reject a newer identity.
    func prepare(
        identity: RealityViewportPreparationRequest.Identity,
        scene: UniversalViewportScene?,
        fallbackOrigin: Point3D,
        capture: () throws -> (@Sendable (Point3D, Int) throws -> ViewportSpatialOverlayProducer.Output)
    ) {
        guard !Task.isCancelled else { return }
        do {
            let spatialOverlay = try capture()
            try Task.checkCancellation()
            let request = RealityViewportPreparationRequest(
                identity: identity,
                scene: scene,
                fallbackOrigin: fallbackOrigin,
                spatialOverlay: spatialOverlay
            )
            guard !Task.isCancelled else { return }
            prepare(request)
        } catch is CancellationError {
            // Cancellation is a lifecycle signal, not a render failure.
        } catch let error as MeshSourcePresentationRenderError {
            guard !Task.isCancelled else { return }
            reject(identity, error: error)
        } catch {
            guard !Task.isCancelled else { return }
            reject(
                identity,
                error: MeshSourcePresentationRenderError(
                    code: .failed,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func start(_ request: RealityViewportPreparationRequest, requestID: UUID) {
        self.requestID = requestID
        let builder = self.builder
        let reusable = current
        // The construction runs inside this detached task, so cancelling the
        // stored handle is what the plan's own cancellation checks observe.
        buildTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<Prepared, MeshSourcePresentationRenderError>?
            do {
                guard request.identity.snapshotID == request.scene?.snapshotID, request.fallbackOrigin.isFinite else {
                    throw RealityViewportSpatialBatch.invalid("Native preparation identity or fallback origin does not match its inputs.")
                }
                let plan: MeshSourcePresentationRenderPlan?
                if let scene = request.scene {
                    if let retained = reusable?.plan, retained.snapshotID == scene.snapshotID {
                        plan = retained
                    } else {
                        plan = try await builder(scene)
                    }
                } else { plan = nil }
                try Task.checkCancellation()
                guard plan?.snapshotID == request.identity.snapshotID else {
                    throw RealityViewportSpatialBatch.invalid("Prepared surface plan belongs to a different snapshot.")
                }
                let first = plan?.occurrences.first?.positions.first
                let origin = first.map { Point3D(x: $0.x, y: $0.y, z: $0.z) } ?? request.fallbackOrigin
                let overlay = try request.spatialOverlay(origin, plan?.retainedByteCount ?? 0)
                let spatial = overlay.spatialBatch
                guard spatial.handleCount == overlay.interactionRecords.count,
                      spatial.retainedSemanticByteCount == (try ViewportSpatialInteractionRecord.retainedByteCount(for: overlay.interactionRecords, limits: spatial.limits)) else {
                    throw RealityViewportSpatialBatch.invalid("Native handles and semantic interaction records do not match.")
                }
                guard spatial.renderOrigin == origin else {
                    throw RealityViewportSpatialBatch.invalid("Spatial geometry does not use the selected native render origin.")
                }
                try Task.checkCancellation()
                let surface = try await RealityViewport.prepare(plan: plan, spatialBatch: spatial, reusing: reusable?.surface)
                try Task.checkCancellation()
                result = .success(Prepared(identity: request.identity, plan: plan, surface: surface, interactionRecords: overlay.interactionRecords))
            } catch is CancellationError {
                // A cancelled build publishes nothing at all. Identity would
                // discard it anyway, but a cancellation is not a failure and is
                // never recorded as one.
                result = nil
            } catch let error as MeshSourcePresentationRenderError {
                result = .failure(error)
            } catch {
                result = .failure(
                    MeshSourcePresentationRenderError(
                        code: .failed,
                        message: String(describing: error)
                    )
                )
            }
            await self?.finish(result: result, identity: request.identity, requestID: requestID)
        }
    }

    /// Cancels the build this cache owns and returns to `idle`, making every
    /// later completion stale.
    func teardown() {
        buildTask?.cancel()
        pendingRequest = nil
        requestID = nil
        current?.surface.invalidateCamera()
        current = nil
        state = .idle
    }

    /// Rejects a failed main-actor capture through the same publication owner.
    /// An in-flight worker cannot subsequently publish over this failure.
    func reject(_ identity: RealityViewportPreparationRequest.Identity, error: MeshSourcePresentationRenderError) {
        buildTask?.cancel()
        pendingRequest = nil
        requestID = nil
        if displaySurface(for: identity) == nil {
            current?.surface.invalidateCamera()
            current = nil
        }
        state = .failed(identity: identity, error: error)
    }

    private struct Prepared: Sendable {
        let identity: RealityViewportPreparationRequest.Identity
        let plan: MeshSourcePresentationRenderPlan?
        let surface: RealityViewport
        let interactionRecords: [ViewportSpatialInteractionRecord]
    }

    private func finish(
        result: Result<Prepared, MeshSourcePresentationRenderError>?,
        identity: RealityViewportPreparationRequest.Identity,
        requestID: UUID
    ) {
        buildTask = nil
        defer {
            if let next = pendingRequest {
                pendingRequest = nil
                start(next.request, requestID: next.id)
            }
        }
        guard let result, case let .preparing(requested) = state,
              identity.sharesDisplayContext(with: requested),
              self.requestID == requestID else { return }
        // CPU plan preparation ran off MainActor; native resources were awaited
        // under RealityKit's isolation contract. Publication only installs the
        // completed owner after display-context and worker-token checks. Only
        // the exact requested identity can become ready for input queries.
        ViewportResponsivenessSignposts.withPlanPublicationInterval {
            switch result {
            case let .success(prepared):
                self.current = prepared
                if requested == identity {
                    state = .ready(identity: identity, plan: prepared.plan, surface: prepared.surface)
                }
            case let .failure(error):
                guard requested == identity else { return }
                if displaySurface(for: identity) == nil { self.current = nil }
                state = .failed(identity: identity, error: error)
            }
        }
    }

    /// A query that arrived before any frame could judge this identity. The
    /// caller may ask again; it must not read this as an answer.
    private func notReadyFailure(_ message: String) -> MeshSourcePresentationRenderError {
        .init(code: .frameNotReady, message: message)
    }

    private func queryFailure(_ message: String) -> MeshSourcePresentationRenderError {
        MeshSourcePresentationRenderError(code: .failed, message: message)
    }
}
