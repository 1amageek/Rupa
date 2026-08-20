/// Handles decoded Agent requests without owning transport or socket lifecycle.
public protocol AgentRequestHandling: Sendable {
    func handle(_ request: AgentRequest) async -> AgentResponse
}
