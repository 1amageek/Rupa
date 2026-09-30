import Synchronization

/// Counts the whole-document work made while it is the task's probe, so a test can prove how
/// many times a path validates a document or evaluates it from scratch. Production code never
/// installs one.
package final class DocumentWorkProbe: Sendable {
    private struct Counts {
        var validations = 0
        var evaluationsFromScratch = 0
        var incrementalEvaluations = 0
    }

    /// The probe of the current task; work done outside `withValue` is not counted.
    @TaskLocal package static var current: DocumentWorkProbe?

    private let counts = Mutex(Counts())

    package init() {}

    /// Full validations of a design document (`ValidatedDesignDocument.init`).
    package var validationCount: Int {
        counts.withLock { $0.validations }
    }

    /// Evaluations that reused no current evaluation (`DocumentEvaluationContextResolver`).
    package var evaluationFromScratchCount: Int {
        counts.withLock { $0.evaluationsFromScratch }
    }

    /// Evaluations seeded by a current evaluation that no longer described the document.
    package var incrementalEvaluationCount: Int {
        counts.withLock { $0.incrementalEvaluations }
    }

    func recordValidation() {
        counts.withLock { $0.validations += 1 }
    }

    func recordEvaluationFromScratch() {
        counts.withLock { $0.evaluationsFromScratch += 1 }
    }

    func recordIncrementalEvaluation() {
        counts.withLock { $0.incrementalEvaluations += 1 }
    }
}
