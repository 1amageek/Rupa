@MainActor
final class ProjectWorkspaceOperationSequencer {
    private var tail: Task<Void, Never>?

    @discardableResult
    func enqueue<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) -> Task<Result, Error> {
        let predecessor = tail
        let task = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { @MainActor in
            _ = await task.result
        }
        return task
    }

    func run<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        try await enqueue(operation).value
    }
}
