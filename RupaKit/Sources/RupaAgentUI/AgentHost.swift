import Foundation
import RupaAgentProtocol
import RupaAgentTransport

public enum AgentHostState: Equatable, Sendable {
    case stopped
    case starting
    case running(socketPath: String)
    case failed(message: String)
}

@MainActor
public final class AgentHost {
    public private(set) var state: AgentHostState

    private let listener: any AgentHostListening
    private let socketPath: AgentSocketPath
    private var lifecycleGeneration: Int

    public init(
        handler: any AgentRequestHandling,
        socketPath: AgentSocketPath = AgentSocketPath()
    ) {
        self.socketPath = socketPath
        self.listener = AgentSocketListener(
            handler: handler,
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
