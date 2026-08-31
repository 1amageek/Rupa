import Synchronization

/// A shared, single-use owner for a response encoding plan.
///
/// The reference identity is intentional: copying this value copies access to
/// one mutex-protected consumption state rather than creating another
/// reservation. The plan is copied out while the lock is held; JSON encoding
/// happens after the lock is released.
public final class AgentResponseEncodingReservation: Sendable {
    public let plan: AgentResponseEncodingPlan
    private let consumptionState = Mutex(false)

    init(plan: AgentResponseEncodingPlan) {
        self.plan = plan
    }

    public var isConsumed: Bool {
        consumptionState.withLock { $0 }
    }

    /// Marks the reservation consumed and returns its immutable plan.
    ///
    /// This method performs no encoding or I/O while holding the mutex. Any
    /// caller that receives the plan owns the one permitted encode attempt.
    func consume() throws -> AgentResponseEncodingPlan {
        try consumptionState.withLock { consumed in
            guard !consumed else {
                throw AgentResponseEncodingError.responsePlanAlreadyConsumed
            }
            consumed = true
            return plan
        }
    }
}
