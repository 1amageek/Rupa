public enum ValidationPolicyFailureReason: String, Codable, Hashable, Sendable {
    case missingRule
    case unacceptableOutcome
    case unacceptableFidelity
    case insufficientRegionCompleteness
    case staleInput
}
