public enum ValidationOutcome: String, Codable, Equatable, Hashable, Sendable {
    case passed
    case failed
    case inconclusive
    case unsupported
}
