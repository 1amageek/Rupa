import Foundation
import RupaProjectAccessPlatform

@MainActor
struct LiveAgentDiscoveryRecordResolver {
    private let reader: any AgentDiscoveryRecordReading

    init(reader: any AgentDiscoveryRecordReading) {
        self.reader = reader
    }

    func resolve(
        waitingForAvailability: Bool,
        excludingGenerations: Set<UInt64> = [],
        deadline: ContinuousClock.Instant
    ) async throws -> AgentDiscoveryRecord {
        while true {
            try checkLiveProjectDeadline(deadline)
            do {
                let record = try reader.read()
                guard !excludingGenerations.contains(record.generation) else {
                    guard waitingForAvailability else {
                        throw AgentDiscoveryError.unavailable(
                            "The published Agent generation has already failed readiness."
                        )
                    }
                    try checkLiveProjectDeadline(deadline)
                    do {
                        try await Task.sleep(for: .milliseconds(20))
                    } catch is CancellationError {
                        throw CancellationError()
                    }
                    continue
                }
                return record
            } catch let error as AgentDiscoveryError {
                guard waitingForAvailability,
                      case .unavailable = error else {
                    throw error
                }
                try checkLiveProjectDeadline(deadline)
                do {
                    try await Task.sleep(for: .milliseconds(20))
                } catch is CancellationError {
                    throw CancellationError()
                }
            }
        }
    }
}
