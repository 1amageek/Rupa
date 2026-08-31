import Foundation
import RupaAgentProtocol
import RupaAgentTransport

public enum AgentHostState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case failed(message: String)
}

@MainActor
public final class AgentHost {
    public private(set) var state: AgentHostState

    private let listener: any AgentHostListening
    private var lifecycleGeneration: Int

    public init(
        handler: any AgentRequestHandling,
        endpoint: UnixSocketEndpoint,
        peerAuthorizer: any AgentPeerAuthorizing
    ) {
        self.listener = AgentSocketListener(
            handler: handler,
            endpoint: endpoint,
            peerAuthorizer: peerAuthorizer
        )
        self.state = .stopped
        self.lifecycleGeneration = 0
    }

    init(
        listener: any AgentHostListening
    ) {
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
            state = .running
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
