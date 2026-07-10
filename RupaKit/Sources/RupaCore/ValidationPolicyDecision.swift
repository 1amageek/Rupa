public enum ValidationPolicyDecision: String, Codable, Equatable, Sendable {
    case allow
    case block
    case override
}
