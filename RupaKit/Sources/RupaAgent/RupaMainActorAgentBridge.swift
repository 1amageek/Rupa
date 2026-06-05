import Foundation
import RupaCore

@MainActor
public final class RupaMainActorAgentBridge {
    private let server: RupaAgentServer

    public init(server: RupaAgentServer = RupaAgentServer()) {
        self.server = server
    }

    @discardableResult
    public func register(
        session: EditorSession,
        path: URL? = nil,
        id: UUID = UUID()
    ) -> UUID {
        server.register(session: session, path: path, id: id)
    }

    public func unregister(id: UUID) {
        server.unregister(id: id)
    }

    public func setSocketPath(_ path: String?) {
        server.socketPath = path
    }

    public func handle(_ request: AgentRequest) -> AgentResponse {
        server.handle(request)
    }
}
