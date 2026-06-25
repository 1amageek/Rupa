import Foundation
import RupaCore

@MainActor
public final class MainActorAgentBridge {
    private let controller: AgentCommandController

    public init(controller: AgentCommandController = AgentCommandController()) {
        self.controller = controller
    }

    @discardableResult
    public func register(
        session: EditorSession,
        path: URL? = nil,
        id: UUID = UUID()
    ) -> UUID {
        controller.register(session: session, path: path, id: id)
    }

    public func unregister(id: UUID) {
        controller.unregister(id: id)
    }

    public func setSocketPath(_ path: String?) {
        controller.socketPath = path
    }

    public func handle(_ request: AgentRequest) -> AgentResponse {
        controller.handle(request)
    }
}
