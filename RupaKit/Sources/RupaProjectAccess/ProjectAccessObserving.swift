import RupaAgentProtocol

/// Observes the reachable live Rupa host without opening a project.
@MainActor
public protocol ProjectAccessObserving: Sendable {
    func capabilities(
        deadline: ContinuousClock.Instant
    ) async throws -> [AgentCapabilityDescriptor]

    func status(
        deadline: ContinuousClock.Instant
    ) async throws -> AgentStatus

    func sessions(
        deadline: ContinuousClock.Instant
    ) async throws -> [WorkspaceSessionSummary]
}
