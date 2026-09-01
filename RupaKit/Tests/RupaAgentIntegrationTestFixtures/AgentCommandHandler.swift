import RupaAgentProtocol

/// Serializes access to the mutable in-process command controller.
public actor AgentCommandHandler: AgentRequestHandling {
    private let controller: AgentCommandController

    public init(controller: sending AgentCommandController = AgentCommandController()) {
        self.controller = controller
    }

    public func handle(_ envelope: AgentRequestEnvelope) async -> AgentHandledResponse {
        .ordinary(controller.handle(envelope.params))
    }
}
