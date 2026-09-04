import Observation
import RupaCore
import RupaCoreTypes
import SwiftCAD

/// The lifecycle of one transient preview evaluation.
///
/// Exactly one revision is described at a time. A `ready` state may carry no
/// cache when the preview document has no active evaluation features; that is a
/// successful result with nothing to project, not a failure.
enum ViewportPreviewEvaluationState {
    case idle
    case preparing(revision: UInt64)
    case ready(revision: UInt64, cache: EvaluatedDocumentCache?)
    case failed(revision: UInt64, message: String)
}

/// Owns the lifetime of one transient, never-published preview evaluation per
/// viewport.
///
/// The viewport builds preview documents that no project authority ever
/// publishes, so no published evaluation can match them. This cache prepares
/// their evaluation off `MainActor` through the existing `EvaluationScheduler`
/// and exposes it only while its revision is still current. Scene construction
/// never evaluates a preview document on the thread that draws it.
///
/// The evaluator is synchronous and does not observe cancellation, so an
/// abandoned evaluation runs to completion and its result is discarded. To keep
/// a drag from launching one kernel evaluation per input event, at most one
/// evaluation is in flight; a revision requested while one is running replaces
/// any earlier waiting request and starts when the running one completes.
@Observable
@MainActor
final class ViewportPreviewEvaluationCache {
    private(set) var state: ViewportPreviewEvaluationState = .idle

    /// The number of evaluations actually started. Coalescing is observable
    /// only through this count: requesting many revisions during one drag must
    /// not start one evaluation per request.
    @ObservationIgnored
    private(set) var startedEvaluationCount = 0

    /// The number of started evaluations that have run to completion. Because an
    /// abandoned evaluation is not stopped, this is how a caller observes that a
    /// discarded result actually arrived and was rejected.
    @ObservationIgnored
    private(set) var completedEvaluationCount = 0

    @ObservationIgnored
    private var isEvaluating = false

    @ObservationIgnored
    private var pendingRequest: Request?

    @ObservationIgnored
    private let scheduler: EvaluationScheduler

    init(scheduler: EvaluationScheduler = EvaluationScheduler()) {
        self.scheduler = scheduler
    }

    /// The evaluation to supply to scene construction for `revision`, or `nil`
    /// while that revision is not `ready`.
    func readyCache(for revision: UInt64) -> EvaluatedDocumentCache? {
        guard case .ready(let readyRevision, let cache) = state,
              readyRevision == revision else {
            return nil
        }
        return cache
    }

    /// Whether `revision` has an evaluation that scene construction may project.
    func isReady(for revision: UInt64) -> Bool {
        guard case .ready(let readyRevision, _) = state else {
            return false
        }
        return readyRevision == revision
    }

    /// The explicit failure recorded for `revision`, or `nil` when that revision
    /// did not fail. A failure is never reported as an empty successful scene.
    func failureMessage(for revision: UInt64) -> String? {
        guard case .failed(let failedRevision, let message) = state,
              failedRevision == revision else {
            return nil
        }
        return message
    }

    /// Requests the evaluation of `document` for `revision`. Repeating the call
    /// for the revision the current state already describes does nothing.
    func prepare(
        document: DesignDocument,
        generation: DocumentGeneration,
        revision: UInt64,
        reusing previous: EvaluatedDocument?,
        objectRegistry: ObjectTypeRegistry
    ) {
        guard describedRevision != revision else {
            return
        }
        state = .preparing(revision: revision)
        let request = Request(
            document: document,
            generation: generation,
            revision: revision,
            previous: previous,
            objectRegistry: objectRegistry
        )
        guard !isEvaluating else {
            pendingRequest = request
            return
        }
        start(request)
    }

    /// Drops the waiting request and returns to `idle`. A running evaluation is
    /// abandoned: its result can no longer reach any state.
    func clear() {
        pendingRequest = nil
        state = .idle
    }

    private struct Request: Sendable {
        let document: DesignDocument
        let generation: DocumentGeneration
        let revision: UInt64
        let previous: EvaluatedDocument?
        let objectRegistry: ObjectTypeRegistry
    }

    private var describedRevision: UInt64? {
        switch state {
        case .idle:
            return nil
        case .preparing(let revision):
            return revision
        case .ready(let revision, _):
            return revision
        case .failed(let revision, _):
            return revision
        }
    }

    private func start(_ request: Request) {
        isEvaluating = true
        startedEvaluationCount += 1
        let scheduler = scheduler
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                scheduler.evaluateResult(
                    document: request.document,
                    generation: request.generation,
                    objectRegistry: request.objectRegistry,
                    reusing: request.previous
                )
            }.value
            self?.finish(result: result, revision: request.revision)
        }
    }

    private func finish(result: DocumentEvaluationResult, revision: UInt64) {
        isEvaluating = false
        completedEvaluationCount += 1
        if describedRevision == revision {
            switch result.snapshot.status {
            case .failed(let message):
                state = .failed(revision: revision, message: message)
            case .valid, .notEvaluated:
                state = .ready(revision: revision, cache: result.evaluationCache)
            }
        }
        if let next = pendingRequest {
            pendingRequest = nil
            start(next)
        }
    }
}
