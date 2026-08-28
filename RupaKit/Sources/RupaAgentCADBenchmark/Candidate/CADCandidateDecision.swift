public enum CADCandidateDecision: Codable, Equatable, Hashable, Sendable {
    case action(CADCandidateAction)
    case unsupported(CADUnsupportedDeclaration)
    case finish(CADOutputRoleBindings)
}
