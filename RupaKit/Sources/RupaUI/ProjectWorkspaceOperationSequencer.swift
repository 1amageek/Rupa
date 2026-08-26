@MainActor
public final class ProjectWorkspaceOperationSequencer {
    private var tail: Task<Void, Never>?

    public init() {}

    @discardableResult
    public func enqueue<Result: Sendable>(
        operationGuard: @escaping @MainActor @Sendable () throws -> Void = {},
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) -> Task<Result, Error> {
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
