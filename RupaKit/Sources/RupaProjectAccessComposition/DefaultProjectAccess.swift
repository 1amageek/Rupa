import RupaAgentProtocol
import RupaProjectAccess

/// Routes one explicit access target without switching authority modes.
@MainActor
public final class DefaultProjectAccess: ProjectAccessOpening, ProjectAccessObserving {
    private let liveOpening: any ProjectAccessOpening
    private let liveObserver: any ProjectAccessObserving
    private let closedOpening: any ProjectAccessOpening

    public init(
        liveOpening: any ProjectAccessOpening,
        liveObserver: any ProjectAccessObserving,
        closedOpening: any ProjectAccessOpening
    ) {
        self.liveOpening = liveOpening
        self.liveObserver = liveObserver
        self.closedOpening = closedOpening
    }

    public convenience init(
        live: LiveProjectAccessOpening,
        closed: ClosedProjectAccessOpening
    ) {
        self.init(
            liveOpening: live,
            liveObserver: live,
            closedOpening: closed
        )
    }

    public func open(
        _ target: ProjectAccessTarget,
        deadline: ContinuousClock.Instant
    ) async throws -> any ProjectAccessSession {
        let validatedTarget = try target.validated()
        switch validatedTarget {
        case .liveProject, .liveSession:
            return try await liveOpening.open(
                validatedTarget,
                deadline: deadline
            )
        case .closedProject:
            return try await closedOpening.open(
                validatedTarget,
                deadline: deadline
            )
        }
    }

    public func status(
        deadline: ContinuousClock.Instant
    ) async throws -> AgentStatus {
        try await liveObserver.status(deadline: deadline)
    }

    public func capabilities(
        deadline: ContinuousClock.Instant
    ) async throws -> [AgentCapabilityDescriptor] {
        try await liveObserver.capabilities(deadline: deadline)
    }

    public func sessions(
        deadline: ContinuousClock.Instant
    ) async throws -> [WorkspaceSessionSummary] {
        try await liveObserver.sessions(deadline: deadline)
    }
}
