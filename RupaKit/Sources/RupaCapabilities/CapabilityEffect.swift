public enum CapabilityEffect: String, Codable, Equatable, Sendable {
    case query
    case sourceMutation
    case workspaceMutation
    case artifactGeneration
    case export
    case externalJob
    case decisionRecording
}
