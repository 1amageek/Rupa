import Foundation

enum CADLIN001DeadlineError: Error, Equatable {
    case exceeded
}

/// Enforces one shared execution deadline across asynchronous LIN-001 phases.
struct CADLIN001Deadline: Sendable {
    let timeoutWallNanoseconds: UInt64

    private let clock = ContinuousClock()
    private let deadline: ContinuousClock.Instant

    init(timeoutWallNanoseconds: UInt64) {
        let bounded = max(1, timeoutWallNanoseconds)
        self.timeoutWallNanoseconds = bounded
        let nanoseconds = Int64(min(bounded, UInt64(Int64.max)))
        self.deadline = clock.now.advanced(by: .nanoseconds(nanoseconds))
    }

    var exceeded: Bool {
        clock.now >= deadline
    }

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let remaining = clock.now.duration(to: deadline)
        guard remaining > .zero else {
            throw CADLIN001DeadlineError.exceeded
        }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: remaining)
                throw CADLIN001DeadlineError.exceeded
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw CADLIN001DeadlineError.exceeded
            }
            return first
        }
    }
}
