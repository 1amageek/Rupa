public enum ValidationRegionCompleteness: String, Codable, Equatable, Hashable, Sendable {
    case complete
    case representative
    case summaryOnly
    case unavailable
}
