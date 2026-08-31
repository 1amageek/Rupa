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
    private var endpoint: AgentHTTPEndpoint?
    private var lifecycleGeneration: UInt64
    private var mayStart: Bool

    public init(
        handler: any AgentRequestHandling,
        key: Data,
        generation: UInt64,
        requestTimeout: Duration = .seconds(30),
        shutdownTimeout: Duration = .seconds(5)
    ) {
        self.listener = AgentHTTPListener(
            handler: handler,
            key: key,
            generation: generation,
            requestedPort: 0,
            requestTimeout: requestTimeout,
            shutdownTimeout: shutdownTimeout
        )
        self.state = .stopped
        self.endpoint = nil
        self.lifecycleGeneration = 0
        self.mayStart = true
    }

    init(
        listener: any AgentHostListening
    ) {
        self.listener = listener
        self.state = .stopped
        self.endpoint = nil
        self.lifecycleGeneration = 0
        self.mayStart = true
    }

    /// Starts the listener and returns its ready loopback endpoint.
    public func start() async throws -> AgentHTTPEndpoint {
        switch state {
        case .running:
            guard let endpoint else {
                throw AgentHostError.missingReadyEndpoint
            }
            return endpoint
        case .starting:
            throw AgentHostError.startAlreadyInProgress
        case .failed:
            throw AgentHostError.listenerLifetimeEnded
        case .stopped:
            guard mayStart else {
                throw AgentHostError.listenerLifetimeEnded
            }
        }

        let generation = advanceLifecycleGeneration()
        state = .starting
        do {
            let endpoint = try await listener.start()
            guard lifecycleGeneration == generation, state == .starting else {
                await listener.stop()
                throw CancellationError()
            }
            self.endpoint = endpoint
            state = .running
            return endpoint
        } catch {
            guard lifecycleGeneration == generation else {
                throw error
            }
            endpoint = nil
            mayStart = false
            state = .failed(message: error.localizedDescription)
            throw error
        }
    }

    /// Bounded-drains the listener. Discovery removal is App composition work.
    public func stop() async {
        guard state != .stopped || mayStart else {
            return
        }

        _ = advanceLifecycleGeneration()
        mayStart = false
        await listener.stop()
        endpoint = nil
        state = .stopped
    }

    @discardableResult
    private func advanceLifecycleGeneration() -> UInt64 {
        if lifecycleGeneration == UInt64.max {
            lifecycleGeneration = 1
        } else {
            lifecycleGeneration += 1
        }
        return lifecycleGeneration
    }
}

protocol AgentHostListening: Sendable {
    func start() async throws -> AgentHTTPEndpoint
    func stop() async
}

extension AgentHTTPListener: AgentHostListening {}
