public enum DomainCapabilityDeterminism: String, Codable, Equatable, Sendable {
    case deterministic
    case deterministicWithDeclaredEnvironment
    case nondeterministic
}
