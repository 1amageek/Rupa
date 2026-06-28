public enum DesignProcessCaseGroupKind: String, Codable, Equatable, Sendable {
    case supported
    case boundary
    case degenerate
    case rejected
    case missing
    case performance
}
