public enum SemanticOwnershipPolicy: String, Codable, Hashable, Sendable {
    case domainOwned
    case universalOwned
    case classified
}
