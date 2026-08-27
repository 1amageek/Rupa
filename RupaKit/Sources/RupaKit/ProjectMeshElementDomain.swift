public enum ProjectMeshElementDomain: String, Codable, CaseIterable, Sendable {
    case vertex
    case edge
    case face
    case corner

    var sortOrder: Int {
        switch self {
        case .vertex:
            0
        case .edge:
            1
        case .face:
            2
        case .corner:
            3
        }
    }
}
