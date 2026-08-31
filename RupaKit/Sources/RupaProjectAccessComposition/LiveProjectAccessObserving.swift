import Foundation
import RupaAgentProtocol

/// Observes the process-lifetime Agent host without starting the application.
@MainActor
public protocol LiveProjectAccessObserving: Sendable {
    func status(
        deadline: ContinuousClock.Instant
    ) async throws -> AgentStatus

    func sessions(
        deadline: ContinuousClock.Instant
    ) async throws -> [WorkspaceSessionSummary]
}
