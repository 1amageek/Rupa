public enum CapabilityResultKind: String, Codable, Equatable, Hashable, Sendable {
    case semanticPayload
    case sourceTransaction
    case workspaceTransaction
    case validationReport
    case artifactReference
    case exportArtifact
    case externalJob
}
