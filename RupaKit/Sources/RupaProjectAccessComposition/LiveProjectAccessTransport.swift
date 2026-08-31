import Foundation
import RupaAgentProtocol
import RupaAgentTransport
import RupaProjectAccessPlatform

/// Internal seam for proving live-session mapping without a second command
/// route. Production binds one authenticated HTTP client to one discovery
/// generation for the lifetime of an access session.
@MainActor
protocol LiveProjectAccessTransport: AnyObject {
    func send(
        _ request: AgentRequest,
        deadline: ContinuousClock.Instant
    ) async throws -> AgentResponse
}

@MainActor
final class LiveProjectAgentClient: LiveProjectAccessTransport {
    private let client: AgentHTTPClient

    init(
        record: AgentDiscoveryRecord,
        requestTimeout: Duration
    ) throws {
        self.client = AgentHTTPClient(
            endpoint: try AgentHTTPEndpoint(port: record.port),
            key: record.key,
            generation: record.generation,
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
