public enum SemanticExtensionMutation: Codable, Equatable, Sendable {
    case upsert(SemanticExtensionEnvelope)
    case remove(SemanticExtensionID)

    public var extensionID: SemanticExtensionID {
        switch self {
        case .upsert(let envelope):
            envelope.id
        case .remove(let extensionID):
            extensionID
        }
    }
}
