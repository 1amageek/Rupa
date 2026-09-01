/// Handles decoded Agent requests without owning transport or socket lifecycle.
public protocol AgentRequestHandling: Sendable {
    func handle(_ envelope: AgentRequestEnvelope) async -> AgentHandledResponse
}
