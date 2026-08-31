import Foundation

enum AgentSocketDeadlineError: Error, Equatable, Sendable {
    case invalidTimeout
    case elapsed
}

struct AgentSocketDeadline: Sendable {
    private static let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000

    let instant: ContinuousClock.Instant

    static func request(timeout: Duration) throws -> AgentSocketDeadline {
        guard timeout > .zero else {
            throw AgentSocketDeadlineError.invalidTimeout
        }
        return AgentSocketDeadline(
            instant: ContinuousClock().now.advanced(by: timeout)
        )
    }

    static func absolute(
        _ instant: ContinuousClock.Instant
    ) throws -> AgentSocketDeadline {
        let deadline = AgentSocketDeadline(instant: instant)
        _ = try deadline.remainingMilliseconds()
        return deadline
    }

    func remainingMilliseconds() throws -> Int32 {
        try Task.checkCancellation()
        let remaining = ContinuousClock().now.duration(to: instant)
        let components = remaining.components
        guard components.seconds >= 0,
              components.attoseconds >= 0 else {
            throw AgentSocketDeadlineError.elapsed
        }

        let (secondsAsMilliseconds, secondsOverflow) = components.seconds
            .multipliedReportingOverflow(by: 1_000)
        guard !secondsOverflow else {
            return Int32.max
        }
        let fractionalMilliseconds = components.attoseconds == 0
            ? 0
            : (components.attoseconds / Self.attosecondsPerMillisecond) + 1
        let (remainingMilliseconds, remainingOverflow) = secondsAsMilliseconds
            .addingReportingOverflow(fractionalMilliseconds)
        guard !remainingOverflow else {
            return Int32.max
        }
        guard remainingMilliseconds > 0 else {
            throw AgentSocketDeadlineError.elapsed
        }
        return Int32(min(remainingMilliseconds, Int64(Int32.max)))
    }
}
