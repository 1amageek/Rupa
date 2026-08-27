import Foundation
import RupaCoreTypes

/// The selector-visible element set emitted by a completed plan step.
public enum MeshEditOutputRole: String, Codable, Equatable, Hashable, Sendable {
    case affectedVertices
    case createdVertices
    case createdEdges
    case createdFaces
    case capFaces
    case sideFaces
    case createdCorners

    var domain: GeometryAttributeDomain {
        switch self {
        case .affectedVertices, .createdVertices:
            .vertex
        case .createdEdges:
            .edge
        case .createdFaces, .capFaces, .sideFaces:
            .face
        case .createdCorners:
            .corner
        }
    }
}
