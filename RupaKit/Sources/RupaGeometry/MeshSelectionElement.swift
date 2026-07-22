import Foundation

public enum MeshSelectionElement: Codable, Equatable, Hashable, Sendable {
    case vertex(MeshVertexID)
    case edge(MeshEdgeID)
    case face(MeshFaceID)
    case corner(MeshCornerID)

    public var domain: GeometryAttributeDomain {
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
