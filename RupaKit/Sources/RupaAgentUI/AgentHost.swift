import Foundation
import RupaAgentRuntime
import RupaAgentTransport
import RupaCore
import RupaUI

public enum AgentHostState: Equatable, Sendable {
    case stopped
    case starting
    case running(socketPath: String)
    case failed(message: String)
}

@MainActor
public final class AgentHost: WorkspaceAgentHost {
    public private(set) var state: AgentHostState

    private let bridge: MainActorAgentBridge
    private let listener: AgentSocketListener
    private let socketPath: AgentSocketPath

    public init(socketPath: AgentSocketPath = AgentSocketPath()) {
        self.socketPath = socketPath
        self.bridge = MainActorAgentBridge()
        self.listener = AgentSocketListener(
            mainActorBridge: bridge,
            socketPath: socketPath
        )
        self.state = .stopped
    }

    public func start() async {
        switch state {
        case .starting, .running:
            return
        case .stopped, .failed:
            break
        }

        state = .starting
        do {
            try await listener.start()
            state = .running(socketPath: socketPath.value)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    public func stop() async {
        guard state != .stopped else {
            return
        }

        await listener.stop()
        state = .stopped
    }

    @discardableResult
    public func register(
        session: EditorSession,
        path: URL? = nil,
        id: UUID = UUID()
    ) -> UUID {
        bridge.register(session: session, path: path, id: id)
    }

    public func unregister(id: UUID) {
        bridge.unregister(id: id)
    }
}
