public enum CADBenchmarkBaselineDrift: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case aggregateContract
    case toolchain
    case agentRoute
    case evaluator
    case manifest
    case expectation
    case capabilityAvailability
    case executionRecords
}
