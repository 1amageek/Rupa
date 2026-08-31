import Foundation
import RupaProjectAccess

@MainActor
final class LiveProjectAccessOperationSequencer {
    private var tail: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var acceptsOperations = true

    func enqueue<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        guard acceptsOperations else {
            throw ProjectAccessError.finished
        }
        try Task.checkCancellation()

        let predecessor = tail
        let current = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { @MainActor in
            _ = await current.result
        }
        return try await withTaskCancellationHandler {
            try await current.value
        } onCancel: {
            current.cancel()
        }
    }

    func finish(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) async {
        if let finishTask {
            await finishTask.value
            return
        }
        acceptsOperations = false
        let predecessor = tail
        let completion = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            await operation()
        }
        finishTask = completion
        tail = completion
        await completion.value
    }
}
