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

    /// The attribute domains in which this operation creates elements that
    /// inherit nothing from a source element. Extruded vertices declare the
    /// selected vertex they duplicate, so the vertex domain stays sourced.
    var unsourcedAttributeDomains: Set<GeometryAttributeDomain> {
        switch self {
        case .primitive(let primitive):
            primitive.unsourcedAttributeDomains
        case .translateElements:
            []
        case .extrudeFaces:
            [.edge, .face, .corner]
        }
    }
}
