import Foundation

public protocol AgentDiscoveryRecordReading: Sendable {
    func read() throws -> AgentDiscoveryRecord
}

public protocol AgentDiscoveryRecordWriting: Sendable {
    func publish(_ record: AgentDiscoveryRecord) throws
    func remove(ifGeneration generation: UInt64) throws
}

public typealias AgentDiscoveryRecordStore = AgentDiscoveryRecordReading & AgentDiscoveryRecordWriting
