public enum DomainCapabilityEffect: String, Codable, Equatable, Sendable {
    case query
    case documentMutation
    case artifactGeneration
    case export
    case externalJob
}
