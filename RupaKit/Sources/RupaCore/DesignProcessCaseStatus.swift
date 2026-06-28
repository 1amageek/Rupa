public enum DesignProcessCaseStatus: String, Codable, Equatable, Sendable {
    case planned
    case supported
    case verified
    case rejected
    case missing
    case blocked
    case measured
}
