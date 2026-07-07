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
public final class AgentHost: WorkspaceAgentSessionPublishing {
    public private(set) var state: AgentHostState

    private let bridge: MainActorAgentBridge
    private let listener: any AgentHostListening
    private let socketPath: AgentSocketPath
    private var lifecycleGeneration: Int

    public init(socketPath: AgentSocketPath = AgentSocketPath()) {
        self.socketPath = socketPath
        self.bridge = MainActorAgentBridge()
        self.listener = AgentSocketListener(
            mainActorBridge: bridge,
            socketPath: socketPath
        )
        self.state = .stopped
        self.lifecycleGeneration = 0
    }

    init(
        socketPath: AgentSocketPath,
        listener: any AgentHostListening
    ) {
        self.socketPath = socketPath
        self.bridge = MainActorAgentBridge()
        self.listener = listener
        self.state = .stopped
        self.lifecycleGeneration = 0
    }

    public func start() async {
        switch state {
        case .starting, .running:
            return
        case .stopped, .failed:
            break
        }

        advanceLifecycleGeneration()
        let generation = lifecycleGeneration
        state = .starting
        do {
            try await listener.start()
            guard lifecycleGeneration == generation else {
                return
            }
            state = .running(socketPath: socketPath.value)
        } catch {
            guard lifecycleGeneration == generation else {
                return
            }
            state = .failed(message: error.localizedDescription)
        }
    }

    public func stop() async {
        guard state != .stopped else {
            return
        }

        advanceLifecycleGeneration()
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

    private func advanceLifecycleGeneration() {
        if lifecycleGeneration == Int.max {
            lifecycleGeneration = 1
        } else {
            lifecycleGeneration += 1
        }
    }
}

protocol AgentHostListening: Sendable {
    func start() async throws
    func stop() async
}

extension AgentSocketListener: AgentHostListening {}
