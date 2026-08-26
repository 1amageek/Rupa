import RupaAgentProtocol

/// Serializes access to the mutable in-process command controller.
public actor AgentCommandHandler: AgentSocketServing {
    private let controller: AgentCommandController

    public init(controller: sending AgentCommandController = AgentCommandController()) {
        self.controller = controller
    }

    public func setSocketPath(_ path: String?) {
        controller.socketPath = path
    }

    public func handle(_ request: AgentRequest) -> AgentResponse {
        controller.handle(request)
    }
}
