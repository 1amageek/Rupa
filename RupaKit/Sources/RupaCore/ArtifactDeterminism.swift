public enum ArtifactDeterminism: String, Codable, Hashable, Sendable {
    case deterministic
    case environmentBound
    case nondeterministic
}
