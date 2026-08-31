import Foundation
import RupaAgentProtocol
import RupaAgentTransport
import RupaAgentUI
import RupaProjectAccessPlatform

@MainActor
final class ApplicationAgentHostLifecycle {
    enum State: Equatable {
        case stopped
        case starting
        case published
        case stopping
        case failed(message: String)
    }

    private let host: AgentHost
    private let discoveryStore: any AgentDiscoveryRecordStore
    private let credential: ApplicationAgentAccessCredential
    private var operationGeneration: UInt64 = 0
    private var publishedGeneration: UInt64?
    private var lifetimeEnded = false

    private(set) var state: State = .stopped

    init(
        handler: any AgentRequestHandling,
        discoveryStore: any AgentDiscoveryRecordStore,
        requestTimeout: Duration = .seconds(30),
        shutdownTimeout: Duration = .seconds(5)
    ) throws {
        let credential = try ApplicationAgentAccessCredential.generate()
        self.credential = credential
        self.discoveryStore = discoveryStore
        self.host = AgentHost(
            handler: handler,
            key: credential.key,
            generation: credential.generation,
            requestTimeout: requestTimeout,
            shutdownTimeout: shutdownTimeout
        )
    }

    init(
        host: AgentHost,
        discoveryStore: any AgentDiscoveryRecordStore,
        credential: ApplicationAgentAccessCredential
    ) {
        self.host = host
        self.discoveryStore = discoveryStore
        self.credential = credential
    }

    func start() async throws {
        switch state {
        case .published:
            return
        case .starting:
            throw AgentHostError.startAlreadyInProgress
        case .stopping, .failed:
            throw AgentHostError.listenerLifetimeEnded
        case .stopped:
            guard !lifetimeEnded else {
                throw AgentHostError.listenerLifetimeEnded
            }
        }

        let operation = advanceOperationGeneration()
        state = .starting
        do {
            let endpoint = try await host.start()
            guard operationGeneration == operation, state == .starting else {
                await host.stop()
                throw CancellationError()
            }
            let record = try AgentDiscoveryRecord(
                port: endpoint.port,
                generation: credential.generation,
                key: credential.key
            )
            try discoveryStore.publish(record)
            publishedGeneration = credential.generation
            state = .published
        } catch {
            guard operationGeneration == operation else {
                throw error
            }
            await host.stop()
            lifetimeEnded = true
            state = .failed(message: error.localizedDescription)
            throw error
        }
    }

    func stop() async throws {
        guard !lifetimeEnded || state != .stopped else {
            return
        }

        _ = advanceOperationGeneration()
        state = .stopping
        await host.stop()
        let generation = publishedGeneration
        publishedGeneration = nil
        lifetimeEnded = true
        do {
            if let generation {
                try discoveryStore.remove(ifGeneration: generation)
            }
            state = .stopped
        } catch {
            state = .failed(message: error.localizedDescription)
            throw error
        }
    }

    @discardableResult
    private func advanceOperationGeneration() -> UInt64 {
        if operationGeneration == UInt64.max {
            operationGeneration = 1
        } else {
            operationGeneration += 1
        }
        return operationGeneration
    }
}
