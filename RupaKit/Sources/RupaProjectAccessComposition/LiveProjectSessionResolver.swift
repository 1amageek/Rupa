import Foundation
import RupaAgentProtocol
import RupaCoreTypes
import RupaProjectAccess

/// Resolves an already registered App-owned workspace through the Agent
/// observation route. It never starts or replaces an application.
@MainActor
final class LiveProjectSessionResolver: ProjectAccessObserving {
    private let transport: any LiveProjectAccessTransport

    init(
        transport: any LiveProjectAccessTransport
    ) {
        self.transport = transport
    }

    public func capabilities(
        deadline: ContinuousClock.Instant
    ) async throws -> [AgentCapabilityDescriptor] {
        let response = try await sendObservation(.capabilities, deadline: deadline)
        guard case .capabilities(let capabilities) = response else {
            throw unexpectedObservationResponse(
                expected: "capabilities",
                actual: response
            )
        }
        return capabilities
    }

    public func status(
        deadline: ContinuousClock.Instant
    ) async throws -> AgentStatus {
        let response = try await sendObservation(.status, deadline: deadline)
        guard case .status(let status) = response else {
            throw unexpectedObservationResponse(
                expected: "status",
                actual: response
            )
        }
        return status
    }

    public func sessions(
        deadline: ContinuousClock.Instant
    ) async throws -> [WorkspaceSessionSummary] {
        let response = try await sendObservation(.sessions, deadline: deadline)
        guard case .sessions(let sessions) = response else {
            throw unexpectedObservationResponse(
                expected: "sessions",
                actual: response
            )
        }
        for session in sessions {
            _ = try canonicalLiveSessionPath(session.path)
        }
        return sessions
    }

    public func resolve(
        sessionID: UUID,
        deadline: ContinuousClock.Instant
    ) async throws -> WorkspaceSessionSummary {
        let matches = try await resolve(deadline: deadline) { summary in
            summary.id == sessionID
        }
        guard let match = matches.first else {
            throw ProjectAccessError.sessionUnavailable(sessionID)
        }
        return match
    }

    public func resolve(
        projectURL: URL,
        deadline: ContinuousClock.Instant
    ) async throws -> WorkspaceSessionSummary {
        let canonicalURL = canonicalLiveProjectURL(projectURL)
        let matches = try await resolve(deadline: deadline) { summary in
            try canonicalLiveSessionPath(summary.path) == canonicalURL
        }

        guard let match = matches.first else {
            throw ProjectAccessError.sessionUnavailable(nil)
        }
        guard matches.count == 1 else {
            throw LiveProjectAccessError.multipleMatchingSessions(canonicalURL)
        }
        return match
    }

    private func resolve(
        deadline: ContinuousClock.Instant,
        matching predicate: (WorkspaceSessionSummary) throws -> Bool
    ) async throws -> [WorkspaceSessionSummary] {
        while true {
            try checkLiveProjectDeadline(deadline)
            let summaries = try await sessions(deadline: deadline)
            var matches: [WorkspaceSessionSummary] = []
            for summary in summaries where try predicate(summary) {
                matches.append(summary)
            }
            if !matches.isEmpty {
                return matches
            }
            try checkLiveProjectDeadline(deadline)
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch is CancellationError {
                throw CancellationError()
            }
        }
    }

    private func sendObservation(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse {
        try checkLiveProjectDeadline(deadline)
        do {
            let response = try await transport.send(request, deadline: deadline)
            try checkLiveProjectDeadline(deadline)
            if case .failure(let error) = response {
                throw error
            }
            return response
        } catch {
            throw mapLiveProjectTransportError(error)
        }
    }

    private func unexpectedObservationResponse(
        expected: String,
        actual: AgentResponse
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "The Agent returned an unexpected \(expected) observation response: \(String(describing: actual))."
        )
    }
}
