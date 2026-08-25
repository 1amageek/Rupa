import RupaGeometry

public enum AuthoredMeshEditCommand: Codable, Equatable, Sendable {
    case setVertexPosition(
        target: AuthoredMeshEditTarget,
        vertexID: MeshVertexID,
        position: GeometryPoint3D
    )
    case addFace(
        target: AuthoredMeshEditTarget,
        vertexIDs: [MeshVertexID]
    )
    case deleteFace(
        target: AuthoredMeshEditTarget,
        faceID: MeshFaceID
    )

    public var target: AuthoredMeshEditTarget {
        switch self {
        case .setVertexPosition(let target, _, _),
             .addFace(let target, _),
             .deleteFace(let target, _):
            target
        }
    }
}
