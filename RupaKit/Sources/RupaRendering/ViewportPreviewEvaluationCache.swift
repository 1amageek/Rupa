import Foundation
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
/// The scheduler call is synchronous inside an owned detached worker, while the
/// evaluation kernel observes that worker's cancellation at its cooperative
/// checkpoints. Replacement and teardown cancel that actual worker. At most
/// one worker is in flight; a revision requested while it is running replaces
/// any earlier waiting request and starts when the cancelled worker exits. A
/// request identity is checked in addition to the revision so a clear/restart
/// with the same revision cannot publish an older completion.
@Observable
@MainActor
final class ViewportPreviewEvaluationCache {
    private(set) var state: ViewportPreviewEvaluationState = .idle

    /// The number of evaluations actually started. Coalescing is observable
    /// only through this count: requesting many revisions during one drag must
    /// not start one evaluation per request.
    @ObservationIgnored
    private(set) var startedEvaluationCount = 0

    /// The number of started workers that have exited. A worker cancelled before
    /// entering the scheduler is counted after it exits, but it never produces
    /// a synthetic preview result.
    @ObservationIgnored
    private(set) var completedEvaluationCount = 0

    @ObservationIgnored
    private var pendingRequest: Request?

    @ObservationIgnored
    private var activeWorker: Task<WorkerResult, Never>?

    @ObservationIgnored
    private var activeRequestID: UUID?

    @ObservationIgnored
    private var currentRequestID: UUID?

    @ObservationIgnored
    private let evaluationOperation: @Sendable (
        DesignDocument,
        DocumentGeneration,
        ObjectTypeRegistry,
        EvaluatedDocument?
    ) -> DocumentEvaluationResult

    init(scheduler: EvaluationScheduler = EvaluationScheduler()) {
        self.evaluationOperation = { document, generation, objectRegistry, previous in
            scheduler.evaluateResult(
                document: document,
                generation: generation,
                objectRegistry: objectRegistry,
                reusing: previous
            )
        }
    }

    /// Creates a cache with an injected synchronous evaluation operation.
    ///
    /// The production initializer delegates to `EvaluationScheduler`. This
    /// narrow seam lets lifecycle tests park the actual detached worker and
    /// return a scheduler-shaped result after cancellation without replacing
    /// the cache's ownership or publication rules.
    init(
        evaluationOperation: @escaping @Sendable (
            DesignDocument,
            DocumentGeneration,
            ObjectTypeRegistry,
            EvaluatedDocument?
        ) -> DocumentEvaluationResult
    ) {
        self.evaluationOperation = evaluationOperation
    }

    deinit { activeWorker?.cancel() }

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
    /// Replacing an in-flight request cancels its actual worker and retains only
    /// this newest request until that worker exits.
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
        let request = Request(
            id: UUID(),
            document: document,
            generation: generation,
            revision: revision,
            previous: previous,
            objectRegistry: objectRegistry
        )
        currentRequestID = request.id
        state = .preparing(revision: revision)
        guard activeWorker == nil else {
            pendingRequest = request
            activeWorker?.cancel()
            return
        }
        start(request)
    }

    /// Drops the waiting request, cancels the actual worker, and returns to
    /// `idle`. A late result can no longer reach any state.
    func clear() {
        pendingRequest = nil
        currentRequestID = nil
        activeWorker?.cancel()
        state = .idle
    }

    /// Records a preview-construction failure after cancelling any evaluation
    /// for the same described revision. A failure reported while another
    /// revision is current is stale and is ignored. When the cache is already
    /// idle, the caller may record a failure for a newly rejected revision.
    func fail(revision: UInt64, message: String) {
        if let describedRevision, describedRevision != revision {
            return
        }
        clear()
        state = .failed(revision: revision, message: message)
    }

    private struct Request: Sendable {
        let id: UUID
        let document: DesignDocument
        let generation: DocumentGeneration
        let revision: UInt64
        let previous: EvaluatedDocument?
        let objectRegistry: ObjectTypeRegistry
    }

    private enum WorkerResult: Sendable {
        case evaluated(DocumentEvaluationResult)
        case cancelled
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
        startedEvaluationCount += 1
        activeRequestID = request.id
        let operation = evaluationOperation
        let worker = Task.detached(priority: .userInitiated) { () -> WorkerResult in
            guard !Task.isCancelled else {
                return .cancelled
            }
            let result = operation(
                request.document,
                request.generation,
                request.objectRegistry,
                request.previous
            )
            guard !Task.isCancelled else {
                return .cancelled
            }
            return .evaluated(result)
        }
        activeWorker = worker
        Task { [weak self, worker] in
            let workerResult = await worker.value
            let workerWasCancelled = worker.isCancelled || Task.isCancelled
            self?.finish(
                workerResult: workerResult,
                revision: request.revision,
                requestID: request.id,
                workerWasCancelled: workerWasCancelled
            )
        }
    }

    private func finish(
        workerResult: WorkerResult,
        revision: UInt64,
        requestID: UUID,
        workerWasCancelled: Bool
    ) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        activeWorker = nil
        completedEvaluationCount += 1
        if !workerWasCancelled,
           currentRequestID == requestID,
           describedRevision == revision,
           case .evaluated(let result) = workerResult {
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
