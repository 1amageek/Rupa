import Foundation
import Observation
import RupaCoreTypes
import RupaGeometry
import RupaViewportScene
import SwiftCAD

/// Prepares one complete native frame off-scene and publishes only matching output.
///
/// The cache owns exactly one build at a time. Preparing a different scene
/// cancels the actual worker and retains only the newest pending request until
/// the worker exits. Cancellation therefore cannot accumulate overlapping GPU
/// allocations. Publication requires both snapshot and request identity, which
/// also rejects a late failure after restarting the same snapshot.
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
    @ObservationIgnored private var current: Prepared?

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
        surface(for: identity)?.isCameraReady(revision: revision) == true
    }

    /// Queries only the exact-ready surface for `identity`. A retained
    /// display-only surface is intentionally not a query authority.
    func surfaceHit(
        at point: CGPoint,
        for identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> (triangle: MeshSourcePresentationTriangle, point: Point3D)? {
        try querySurface(for: identity).surfaceHit(at: point, revision: revision)
    }

    /// Resolves the native priority order without granting display-only frames authority.
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
        switch state {
        case let .ready(current, _, surface) where current == identity:
            return surface
        case let .failed(current, error) where current == identity:
            throw error
        case .idle:
            throw queryFailure("The native surface query is unavailable before preparation.")
        case .preparing:
            throw queryFailure("The native surface query is unavailable while preparation is in progress.")
        case .ready:
            throw queryFailure("The native surface query uses a stale preparation identity.")
        case .failed:
            throw queryFailure("The native surface query uses a stale failed preparation identity.")
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
        guard let current, current.identity == identity, let plan = current.plan else { return nil }
        return try MeshSourcePresentationMeshElementResolver.resolve(
            at: point, domain: domain, in: plan,
            project: { try self.project($0, for: identity, revision: revision) },
            surfaceHit: { candidate in
                if candidate == point { return pointerHit?.triangle }
                return try self.surfaceHit(at: candidate, for: identity, revision: revision)?.triangle
            }
        )
    }


    /// Retains a complete display during an overlay-only replacement. This is
    /// not a query authority: handles and CAD queries still require exact readiness.
    func displaySurface(for identity: RealityViewportPreparationRequest.Identity) -> RealityViewport? {
        guard let requested = state.identity,
              requested.scene == identity.scene, requested.snapshotID == identity.snapshotID,
              let current, current.identity.scene == identity.scene,
              current.identity.snapshotID == identity.snapshotID else { return nil }
        return current.surface
    }

    func interactionRecord(at index: UInt32, for identity: RealityViewportPreparationRequest.Identity) -> ViewportSpatialInteractionRecord? {
        guard case let .ready(readyIdentity, _, surface) = state, readyIdentity == identity,
              let current, current.surface === surface,
              Int(index) < current.interactionRecords.count else { return nil }
        return current.interactionRecords[Int(index)]
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
        buildTask?.cancel()
        let requestID = UUID()
        self.requestID = requestID
        if displaySurface(for: request.identity) == nil {
            current?.surface.invalidateCamera()
            // Retain only immutable asset reuse through the existing worker.
            // Display and queries still reject this old frame identity.
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
        guard let result, case let .preparing(current) = state,
              current == identity, self.requestID == requestID else { return }
        // CPU plan preparation ran off MainActor; native resources were awaited
        // under RealityKit's isolation contract. Publication only installs the
        // completed owner after both snapshot and request identity checks.
        ViewportResponsivenessSignposts.withPlanPublicationInterval {
            switch result {
            case let .success(prepared):
                self.current = prepared
                state = .ready(identity: identity, plan: prepared.plan, surface: prepared.surface)
            case let .failure(error):
                if displaySurface(for: identity) == nil { self.current = nil }
                state = .failed(identity: identity, error: error)
            }
        }
    }

    private func queryFailure(_ message: String) -> MeshSourcePresentationRenderError {
        MeshSourcePresentationRenderError(code: .failed, message: message)
    }
}
