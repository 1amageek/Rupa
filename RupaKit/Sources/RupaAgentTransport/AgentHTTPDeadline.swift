import Foundation

struct AgentHTTPDeadline: Sendable {
    private static let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000

    let instant: ContinuousClock.Instant

    static func request(timeout: Duration) throws -> Self {
        guard timeout > .zero else {
            throw AgentHTTPError.deadlineExceeded
        }
        return Self(instant: ContinuousClock().now.advanced(by: timeout))
    }

    static func absolute(_ instant: ContinuousClock.Instant) throws -> Self {
        let deadline = Self(instant: instant)
        _ = try deadline.remainingMilliseconds()
        return deadline
    }

    func remainingMilliseconds() throws -> Int32 {
        try Task.checkCancellation()
        let remaining = ContinuousClock().now.duration(to: instant)
        let components = remaining.components
        guard components.seconds >= 0, components.attoseconds >= 0 else {
            throw AgentHTTPError.deadlineExceeded
        }
        let (secondsAsMilliseconds, secondsOverflow) = components.seconds
            .multipliedReportingOverflow(by: 1_000)
        guard !secondsOverflow else { return Int32.max }
        let fractionalMilliseconds = components.attoseconds == 0
            ? 0
            : (components.attoseconds / Self.attosecondsPerMillisecond) + 1
        let (milliseconds, overflow) = secondsAsMilliseconds
            .addingReportingOverflow(fractionalMilliseconds)
        guard !overflow else { return Int32.max }
        guard milliseconds > 0 else { throw AgentHTTPError.deadlineExceeded }
        return Int32(min(milliseconds, Int64(Int32.max)))
    }
}
