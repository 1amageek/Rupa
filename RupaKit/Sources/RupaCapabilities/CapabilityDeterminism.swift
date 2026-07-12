public enum CapabilityDeterminism: String, Codable, Equatable, Sendable {
    case deterministic
    case deterministicWithDeclaredEnvironment
    case nondeterministic
}
