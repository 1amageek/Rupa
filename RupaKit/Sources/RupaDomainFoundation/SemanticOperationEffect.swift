public enum SemanticOperationEffect: String, Codable, Sendable, Equatable, Hashable {
    case sourceMutation
    case workspaceMutation
    case query
    case export
    case lifecycle
    case externalJob
    case meshMutation
}
