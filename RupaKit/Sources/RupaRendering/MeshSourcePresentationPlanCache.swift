import Observation
import RupaCoreTypes
import RupaViewportScene

/// Prepares one presentation render plan per scene identity off `MainActor`
/// and publishes the outcome back on `MainActor` as an observable state.
///
/// The cache owns exactly one build at a time. Preparing a different scene
/// cancels the build in flight before it starts the next one, so an abandoned
/// build stops at its next cancellation boundary instead of running to
/// completion. A completion is published only while the state is still
/// `preparing` the same `EvaluationSnapshotID`, which discards a stale success
/// and a stale failure by the same rule.
@Observable
@MainActor
final class MeshSourcePresentationPlanCache {
    /// Builds a plan for one scene. Injected so a test can decide when a build
    /// completes without depending on construction timing.
    typealias Builder = @Sendable (UniversalViewportScene) async throws -> MeshSourcePresentationRenderPlan

    private(set) var state: MeshSourcePresentationPlanState = .idle

    @ObservationIgnored private let builder: Builder
    @ObservationIgnored private var buildTask: Task<Void, Never>?

    init(
        builder: @escaping Builder = { scene in
            try MeshSourcePresentationRenderPlan(scene: scene)
        }
    ) {
        self.builder = builder
    }

    /// The plan for `scene`, or `nil` while the cache is idle, preparing, or
    /// holding a result that belongs to a different scene identity.
    func plan(for scene: UniversalViewportScene) -> MeshSourcePresentationRenderPlan? {
        guard case let .ready(snapshotID, plan) = state,
              snapshotID == scene.snapshotID else {
            return nil
        }
        return plan
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
        state = .preparing(snapshotID: snapshotID)
        let builder = self.builder
        // The construction runs inside this detached task, so cancelling the
        // stored handle is what the plan's own cancellation checks observe.
        buildTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<MeshSourcePresentationRenderPlan, MeshSourcePresentationRenderError>
            do {
                result = .success(try await builder(scene))
            } catch is CancellationError {
                // A cancelled build publishes nothing at all. Identity would
                // discard it anyway, but a cancellation is not a failure and is
                // never recorded as one.
                return
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
            await self?.finish(result: result, snapshotID: snapshotID)
        }
    }

    /// Cancels the build this cache owns and returns to `idle`, making every
    /// later completion stale.
    func teardown() {
        buildTask?.cancel()
        buildTask = nil
        state = .idle
    }

    private func finish(
        result: Result<MeshSourcePresentationRenderPlan, MeshSourcePresentationRenderError>,
        snapshotID: EvaluationSnapshotID
    ) {
        guard case let .preparing(current) = state,
              current == snapshotID else {
            return
        }
        // Publication is now only this state assignment. Construction already
        // ran off `MainActor`, so the interval the acceptance table charges to
        // a frame is measured here and nowhere else.
        ViewportResponsivenessSignposts.withPlanPublicationInterval {
            switch result {
            case let .success(plan):
                state = .ready(snapshotID: snapshotID, plan: plan)
            case let .failure(error):
                state = .failed(snapshotID: snapshotID, error: error)
            }
        }
        buildTask = nil
    }
}
