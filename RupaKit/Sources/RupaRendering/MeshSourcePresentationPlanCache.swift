import Foundation
import Observation
import RupaCoreTypes
import RupaViewportScene

/// Prepares one presentation render plan per scene identity off `MainActor`
/// and publishes the outcome back on `MainActor` as an observable state.
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
    @ObservationIgnored private var pendingRequest: (scene: UniversalViewportScene, id: UUID)?

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
        guard case let .ready(snapshotID, plan, _) = state,
              snapshotID == scene.snapshotID else {
            return nil
        }
        return plan
    }

    func surface(for scene: UniversalViewportScene) -> RealityViewport? {
        guard case let .ready(snapshotID, _, surface) = state,
              snapshotID == scene.snapshotID else { return nil }
        return surface
    }

    /// The failure recorded for `scene`, or `nil` when the current state is not
    /// a failure that belongs to this scene identity.
    func failure(for scene: UniversalViewportScene) -> MeshSourcePresentationRenderError? {
        guard case let .failed(snapshotID, error) = state,
              snapshotID == scene.snapshotID else {
            return nil
        }
        return error
    }

    /// Whether a build for this scene identity is still in flight.
    func isPreparing(_ scene: UniversalViewportScene) -> Bool {
        guard case let .preparing(snapshotID) = state else {
            return false
        }
        return snapshotID == scene.snapshotID
    }

    /// Starts a build for `scene` unless the cache already describes that scene
    /// identity. Must not be called from a SwiftUI `body`: it publishes
    /// `preparing` synchronously and mutating observable state during a view
    /// update is undefined behavior.
    func prepare(for scene: UniversalViewportScene) {
        let snapshotID = scene.snapshotID
        guard state.snapshotID != snapshotID else {
            return
        }
        buildTask?.cancel()
        let requestID = UUID()
        self.requestID = requestID
        state = .preparing(snapshotID: snapshotID)
        if buildTask != nil {
            pendingRequest = (scene, requestID)
        } else {
            start(scene, requestID: requestID)
        }
    }

    private func start(_ scene: UniversalViewportScene, requestID: UUID) {
        let snapshotID = scene.snapshotID
        let builder = self.builder
        // The construction runs inside this detached task, so cancelling the
        // stored handle is what the plan's own cancellation checks observe.
        buildTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<Prepared, MeshSourcePresentationRenderError>?
            do {
                let plan = try await builder(scene)
                try Task.checkCancellation()
                let surface = try await RealityViewport.prepare(plan: plan)
                try Task.checkCancellation()
                result = .success(Prepared(plan: plan, surface: surface))
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
            await self?.finish(result: result, snapshotID: snapshotID, requestID: requestID)
        }
    }

    /// Cancels the build this cache owns and returns to `idle`, making every
    /// later completion stale.
    func teardown() {
        buildTask?.cancel()
        pendingRequest = nil
        requestID = nil
        state = .idle
    }

    private struct Prepared: Sendable {
        let plan: MeshSourcePresentationRenderPlan
        let surface: RealityViewport
    }

    private func finish(
        result: Result<Prepared, MeshSourcePresentationRenderError>?,
        snapshotID: EvaluationSnapshotID,
        requestID: UUID
    ) {
        buildTask = nil
        defer {
            if let next = pendingRequest {
                pendingRequest = nil
                start(next.scene, requestID: next.id)
            }
        }
        guard let result, case let .preparing(current) = state,
              current == snapshotID, self.requestID == requestID else { return }
        // CPU plan preparation ran off MainActor; native resources were awaited
        // under RealityKit's isolation contract. Publication only installs the
        // completed owner after both snapshot and request identity checks.
        ViewportResponsivenessSignposts.withPlanPublicationInterval {
            switch result {
            case let .success(prepared):
                state = .ready(snapshotID: snapshotID, plan: prepared.plan, surface: prepared.surface)
            case let .failure(error):
                state = .failed(snapshotID: snapshotID, error: error)
            }
        }
    }
}
