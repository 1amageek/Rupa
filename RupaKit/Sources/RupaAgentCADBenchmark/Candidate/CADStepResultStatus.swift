public enum CADStepResultStatus: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case published
    case unchanged
    case failed
}
