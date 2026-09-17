@MainActor
public final class ProjectWorkspaceOperationSequencer {
    private var tail: Task<Void, Never>?
    private var pendingReplacement: PendingReplacement?

    private final class PendingReplacement {
        let key: AnyHashable
        var operation: @MainActor @Sendable () async -> Void

        init(key: AnyHashable, operation: @escaping @MainActor @Sendable () async -> Void) {
            self.key = key
            self.operation = operation
        }
    }

    public init() {}

    /// Observes already-enqueued work without introducing an ordering barrier.
    var currentCompletion: Task<Void, Never>? { tail }

    @discardableResult
    public func enqueue<Result: Sendable>(
        operationGuard: @escaping @MainActor @Sendable () throws -> Void = {},
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) -> Task<Result, Error> {
        pendingReplacement = nil
        let predecessor = tail
        let task = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            try Task.checkCancellation()
            try operationGuard()
            return try await operation()
        }
        tail = Task { @MainActor in
            _ = await task.result
        }
        return task
    }

    /// Replaces only a consecutive, unstarted absolute-value edit. Ordinary
    /// operations and different keys are ordering barriers; running work is
    /// never cancelled. The caller owns failure reporting for the executed edit.
    func enqueueReplacingPending<Key: Hashable>(
        key: Key,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        if let pendingReplacement, pendingReplacement.key == AnyHashable(key) {
            pendingReplacement.operation = operation
            return
        }
        let pending = PendingReplacement(key: AnyHashable(key), operation: operation)
        _ = enqueue {
            if self.pendingReplacement === pending { self.pendingReplacement = nil }
            await pending.operation()
        }
        pendingReplacement = pending
    }

    public func run<Result: Sendable>(
        operationGuard: @escaping @MainActor @Sendable () throws -> Void = {},
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        let task = enqueue(operationGuard: operationGuard, operation)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
