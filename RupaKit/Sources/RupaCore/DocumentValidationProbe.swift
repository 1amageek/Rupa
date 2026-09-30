import Synchronization

/// Counts the document validations made while it is the task's probe, so a test can prove how
/// many times a path validates a document. Production code never installs one.
package final class DocumentValidationProbe: Sendable {
    /// The probe of the current task; validations made outside `withValue` are not counted.
    @TaskLocal package static var current: DocumentValidationProbe?

    private let count = Mutex(0)

    package init() {}

    package var validationCount: Int {
        count.withLock { $0 }
    }

    func recordValidation() {
        count.withLock { $0 += 1 }
    }
}
