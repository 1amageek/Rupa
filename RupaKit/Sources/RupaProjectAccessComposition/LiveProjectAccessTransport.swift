import Foundation
import RupaAgentProtocol
import RupaAgentTransport

/// Internal seam for proving live-session mapping without a second command
/// route. Production uses the injected endpoint through `AgentClient`.
@MainActor
protocol LiveProjectAccessTransport: AnyObject {
    func send(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse
}

@MainActor
final class LiveProjectAgentClient: LiveProjectAccessTransport {
    private let client: AgentClient

    init(
        endpoint: UnixSocketEndpoint,
        requestTimeout: Duration
    ) {
        self.client = AgentClient(
            endpoint: endpoint,
            requestTimeout: requestTimeout
        )
    }

    func send(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse {
        try await client.send(request, deadline: deadline)
    }
}
