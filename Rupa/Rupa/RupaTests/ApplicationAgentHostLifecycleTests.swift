import Foundation
import RupaAgentProtocol
import RupaProjectAccessPlatform
import Synchronization
import Testing
@testable import Rupa

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAgentHostPublishesOnlyAReadyListenerAndRemovesItsGeneration() async throws {
    let store = RecordingAgentDiscoveryStore()
    let lifecycle = try ApplicationAgentHostLifecycle(
        handler: ApplicationAgentStatusHandler(),
        discoveryStore: store,
        requestTimeout: .seconds(5),
        shutdownTimeout: .seconds(1)
    )

    try await lifecycle.start()
    let record = try store.read()
    #expect(lifecycle.state == .published)
    #expect(record.port != 0)
    #expect(record.generation != 0)
    #expect(record.key.count == AgentDiscoveryRecord.keyByteCount)

    try await lifecycle.stop()
    #expect(lifecycle.state == .stopped)
    #expect(store.removedGenerations() == [record.generation])
    #expect(throws: AgentDiscoveryError.self) {
        _ = try store.read()
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAgentHostStopsListenerWhenDiscoveryPublicationFails() async throws {
    let store = RecordingAgentDiscoveryStore(
        publicationError: .unauthorized("Fixture rejection.")
    )
    let lifecycle = try ApplicationAgentHostLifecycle(
        handler: ApplicationAgentStatusHandler(),
        discoveryStore: store,
        requestTimeout: .seconds(5),
        shutdownTimeout: .seconds(1)
    )

    await #expect(throws: AgentDiscoveryError.unauthorized("Fixture rejection.")) {
        try await lifecycle.start()
    }
    guard case .failed = lifecycle.state else {
        Issue.record("Expected a terminal lifecycle failure.")
        return
    }
    #expect(store.removedGenerations().isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func applicationAgentHostDoesNotRemoveANewerDiscoveryGeneration() async throws {
    let store = RecordingAgentDiscoveryStore()
    let lifecycle = try ApplicationAgentHostLifecycle(
        handler: ApplicationAgentStatusHandler(),
        discoveryStore: store,
        requestTimeout: .seconds(5),
        shutdownTimeout: .seconds(1)
    )

    try await lifecycle.start()
    let publishedRecord = try store.read()
    let newerGeneration = publishedRecord.generation == UInt64.max
        ? UInt64(1)
        : publishedRecord.generation + 1
    let newerRecord = try AgentDiscoveryRecord(
        port: publishedRecord.port,
        generation: newerGeneration,
        key: publishedRecord.key
    )
    store.replaceForTesting(with: newerRecord)

    await #expect(
        throws: AgentDiscoveryError.staleGeneration(
            expected: publishedRecord.generation,
            actual: newerGeneration
        )
    ) {
        try await lifecycle.stop()
    }
    #expect(try store.read() == newerRecord)
    #expect(store.removedGenerations().isEmpty)
}

private struct ApplicationAgentStatusHandler: AgentRequestHandling {
    func handle(_ request: AgentRequest) async -> AgentResponse {
        .status(AgentStatus(running: true, sessionCount: 0))
    }
}

private final class RecordingAgentDiscoveryStore:
    AgentDiscoveryRecordStore,
    Sendable {
    private struct State: Sendable {
        var record: AgentDiscoveryRecord?
        var removedGenerations: [UInt64] = []
    }

    private let state = Mutex(State())
    private let publicationError: AgentDiscoveryError?

    init(publicationError: AgentDiscoveryError? = nil) {
        self.publicationError = publicationError
    }

    func read() throws -> AgentDiscoveryRecord {
        try state.withLock { state in
            guard let record = state.record else {
                throw AgentDiscoveryError.unavailable("Fixture has no record.")
            }
            return record
        }
    }

    func publish(_ record: AgentDiscoveryRecord) throws {
        if let publicationError {
            throw publicationError
        }
        state.withLock { state in
            state.record = record
        }
    }

    func remove(ifGeneration generation: UInt64) throws {
        try state.withLock { state in
            guard state.record?.generation == generation else {
                throw AgentDiscoveryError.staleGeneration(
                    expected: generation,
                    actual: state.record?.generation
                )
            }
            state.removedGenerations.append(generation)
            state.record = nil
        }
    }

    func removedGenerations() -> [UInt64] {
        state.withLock { $0.removedGenerations }
    }

    func replaceForTesting(with record: AgentDiscoveryRecord) {
        state.withLock { state in
            state.record = record
        }
    }
}
