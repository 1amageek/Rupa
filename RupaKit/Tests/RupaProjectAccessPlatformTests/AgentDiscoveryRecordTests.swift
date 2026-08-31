import Foundation
import Synchronization
import Testing
@testable import RupaProjectAccessPlatform

@Suite(.serialized)
struct AgentDiscoveryRecordTests {
    @Test(.timeLimit(.minutes(1)))
    func recordRoundTripsWithExactCredentialShape() throws {
        let key = Data(repeating: 0xA5, count: AgentDiscoveryRecord.keyByteCount)
        let record = try AgentDiscoveryRecord(port: 42, generation: 8, key: key)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let decoded = try JSONDecoder().decode(AgentDiscoveryRecord.self, from: data)
        #expect(decoded == record)
        #expect(decoded.key.count == AgentDiscoveryRecord.keyByteCount)
        #expect(decoded.port == 42)
        #expect(decoded.generation == 8)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidRecordValuesAreRejected() {
        let key = Data(repeating: 0, count: AgentDiscoveryRecord.keyByteCount)
        #expect(throws: AgentDiscoveryError.invalidPort) {
            try AgentDiscoveryRecord(port: 0, generation: 1, key: key)
        }
        #expect(throws: AgentDiscoveryError.invalidGeneration) {
            try AgentDiscoveryRecord(port: 1, generation: 0, key: key)
        }
        #expect(throws: AgentDiscoveryError.invalidKeyLength(31)) {
            try AgentDiscoveryRecord(port: 1, generation: 1, key: Data(repeating: 0, count: 31))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func conditionalRemovalPreservesAReplacementGeneration() throws {
        let store = InMemoryDiscoveryStore()
        let first = try AgentDiscoveryRecord(
            port: 1,
            generation: 10,
            key: Data(repeating: 1, count: AgentDiscoveryRecord.keyByteCount)
        )
        let replacement = try AgentDiscoveryRecord(
            port: 2,
            generation: 11,
            key: Data(repeating: 2, count: AgentDiscoveryRecord.keyByteCount)
        )
        try store.publish(first)
        try store.publish(replacement)
        #expect(throws: AgentDiscoveryError.staleGeneration(expected: 10, actual: 11)) {
            try store.remove(ifGeneration: 10)
        }
        #expect(try store.read() == replacement)
        try store.remove(ifGeneration: 11)
        #expect(throws: AgentDiscoveryError.unavailable("empty")) {
            try store.read()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func keychainConfigurationIsExplicitlyInjected() {
        let store = KeychainAgentDiscoveryStore(service: "", account: "account", accessGroup: "group")
        #expect(throws: AgentDiscoveryError.invalidConfiguration) {
            try store.read()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func productConfigurationOwnsTheRequestBudget() {
        #expect(
            RupaProductAccessConfiguration.current.requestTimeout
                == .seconds(120)
        )
    }
}

private final class InMemoryDiscoveryStore: AgentDiscoveryRecordStore, Sendable {
    private let value = Mutex<AgentDiscoveryRecord?>(nil)

    func read() throws -> AgentDiscoveryRecord {
        try value.withLock { record in
            guard let record else { throw AgentDiscoveryError.unavailable("empty") }
            return record
        }
    }

    func publish(_ record: AgentDiscoveryRecord) throws {
        value.withLock { value in
            value = record
        }
    }

    func remove(ifGeneration generation: UInt64) throws {
        try value.withLock { value in
            guard let current = value else { return }
            guard current.generation == generation else {
                throw AgentDiscoveryError.staleGeneration(
                    expected: generation,
                    actual: current.generation
                )
            }
            value = nil
        }
    }
}
