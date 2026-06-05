import Foundation
import RupaAgent
import RupaCore

public enum RupaAgentHostState: Equatable, Sendable {
    case stopped
    case starting
    case running(socketPath: String)
    case failed(message: String)
}

@MainActor
public final class RupaAgentHost {
    public private(set) var state: RupaAgentHostState

    private let bridge: RupaMainActorAgentBridge
    private let listener: RupaAgentSocketListener
    private let socketPath: RupaAgentSocketPath

    public init(socketPath: RupaAgentSocketPath = RupaAgentSocketPath()) {
        self.socketPath = socketPath
        self.bridge = RupaMainActorAgentBridge()
        self.listener = RupaAgentSocketListener(
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
