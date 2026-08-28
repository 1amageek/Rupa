public enum CADBenchmarkRunStatus: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case valid
    case baselineDrift
    case invalid
}
