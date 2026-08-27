import Foundation

/// One provider-independent primitive or semantic Mesh edit operation.
public enum MeshEditOperation: Codable, Equatable, Sendable {
    case primitive(MeshPrimitiveEdit)
    case translateElements(MeshElementSelector, offset: GeometryVector3D)
    case extrudeFaces(MeshElementSelector, offset: GeometryVector3D)

    var outputRoles: Set<MeshEditOutputRole> {
        switch self {
        case .primitive(let primitive):
            primitive.outputRoles
        case .translateElements:
            [.affectedVertices]
        case .extrudeFaces:
            [
                .createdVertices,
                .createdEdges,
                .createdFaces,
                .capFaces,
                .sideFaces,
                .createdCorners,
            ]
        }
    }

    var isTopologyMutation: Bool {
        switch self {
        case .primitive(let primitive):
            primitive.isTopologyMutation
        case .translateElements:
            false
        case .extrudeFaces:
            true
        }
    }
}
