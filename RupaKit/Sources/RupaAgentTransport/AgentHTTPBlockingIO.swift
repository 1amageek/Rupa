import Darwin
import Foundation

/// Keeps blocking POSIX I/O off Swift's cooperative executor.
enum AgentHTTPBlockingIO {
    struct ReadResult: Sendable {
        let message: AgentHTTPWire.Message
        let pending: Data
    }

    static func connect(
        to endpoint: AgentHTTPEndpoint,
        deadline: AgentHTTPDeadline
    ) async throws -> Int32 {
        let descriptor = try AgentHTTPWire.makeConnectionDescriptor()
        do {
            try await run(descriptor: descriptor) {
                try AgentHTTPWire.connect(
                    descriptor,
                    to: endpoint,
                    deadline: deadline
                )
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func readMessage(
        from descriptor: Int32,
        pending: Data,
        deadline: AgentHTTPDeadline
    ) async throws -> ReadResult {
        try await run(descriptor: descriptor) {
            var nextPending = pending
            let message = try AgentHTTPWire.readMessage(
                from: descriptor,
                pending: &nextPending,
                deadline: deadline
            )
            return ReadResult(message: message, pending: nextPending)
        }
    }

    static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        deadline: AgentHTTPDeadline
    ) async throws {
        try await run(descriptor: descriptor) {
            try AgentHTTPWire.writeAll(data, to: descriptor, deadline: deadline)
        }
    }

    /// Returns success when the complete bytes reached the socket even if task
    /// cancellation raced immediately after that completion. The caller must
    /// record its dispatch boundary before observing cancellation again.
    static func writeSemanticRequest(
        _ data: Data,
        to descriptor: Int32,
        deadline: AgentHTTPDeadline
    ) async throws {
        try await run(
            descriptor: descriptor,
            checkCancellationAfterSuccess: false
        ) {
            try AgentHTTPWire.writeAll(data, to: descriptor, deadline: deadline)
        }
    }

    private static func run<Output: Sendable>(
        descriptor: Int32,
        checkCancellationAfterSuccess: Bool = true,
        operation: @escaping @Sendable () throws -> Output
    ) async throws -> Output {
        try await withTaskCancellationHandler {
            do {
                let result = try await withCheckedThrowingContinuation { continuation in
                    Thread.detachNewThread {
                        continuation.resume(with: Swift.Result { try operation() })
                    }
                }
                if checkCancellationAfterSuccess {
                    try Task.checkCancellation()
                }
                return result
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            Darwin.shutdown(descriptor, SHUT_RDWR)
        }
    }
}
