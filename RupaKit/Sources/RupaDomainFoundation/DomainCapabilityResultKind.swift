public enum DomainCapabilityResultKind: String, Codable, Equatable, Hashable, Sendable {
    case semanticPayload
    case documentTransaction
    case validationReport
    case artifactReference
    case exportArtifact
    case externalJob
}
