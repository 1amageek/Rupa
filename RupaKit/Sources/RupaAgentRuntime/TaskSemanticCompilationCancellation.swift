import RupaDomainFoundation
import Synchronization

/// Forwards cooperative task cancellation into the synchronous compiler port.
final class TaskSemanticCompilationCancellation: SemanticCompilationCancellation, Sendable {
    private let cancelled = Mutex(false)

    init(isCancelled: Bool = false) {
        if isCancelled {
            cancelled.withLock { $0 = true }
        }
    }

    var isCancelled: Bool {
        cancelled.withLock { $0 }
    }

    func cancel() {
        cancelled.withLock { $0 = true }
    }
}
