import Foundation
import RupaCoreTypes

/// A low-level topology or position edit used inside a Mesh edit plan.
public enum MeshPrimitiveEdit: Codable, Equatable, Sendable {
    case setVertexPositions([MeshVertexPositionEdit])
    case addFace(vertexIDs: [MeshVertexID])
    case deleteFaces(MeshElementSelector)

    var outputRoles: Set<MeshEditOutputRole> {
        switch self {
        case .setVertexPositions:
            [.affectedVertices]
        case .addFace:
            [.createdFaces, .createdEdges, .createdCorners]
        case .deleteFaces:
            []
        }
    }

    var isTopologyMutation: Bool {
        switch self {
        case .setVertexPositions:
            false
        case .addFace, .deleteFaces:
            true
        }
    }

    /// The attribute domains in which this edit creates elements that inherit
    /// nothing from a source element.
    var unsourcedAttributeDomains: Set<GeometryAttributeDomain> {
        switch self {
        case .setVertexPositions, .deleteFaces:
            []
        case .addFace:
            [.edge, .face, .corner]
        }
    }
}
