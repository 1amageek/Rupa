import RupaCoreTypes

public enum ProjectMeshElementReference: Codable, Equatable, Hashable, Sendable {
    case vertex(MeshVertexID)
    case edge(MeshEdgeID)
    case face(MeshFaceID)
    case corner(MeshCornerID)

    public var domain: ProjectMeshElementDomain {
        switch self {
        case .vertex:
            .vertex
        case .edge:
            .edge
        case .face:
            .face
        case .corner:
            .corner
        }
    }
}
