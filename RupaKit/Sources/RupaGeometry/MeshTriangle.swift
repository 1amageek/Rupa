import Foundation

public struct MeshTriangle: Codable, Equatable, Sendable {
    public var faceID: MeshFaceID
    public var vertexIDs: (MeshVertexID, MeshVertexID, MeshVertexID)

    public init(
        faceID: MeshFaceID,
        vertexIDs: (MeshVertexID, MeshVertexID, MeshVertexID)
    ) {
        self.faceID = faceID
        self.vertexIDs = vertexIDs
    }

    public static func == (lhs: MeshTriangle, rhs: MeshTriangle) -> Bool {
        lhs.faceID == rhs.faceID && lhs.vertexIDs.0 == rhs.vertexIDs.0
            && lhs.vertexIDs.1 == rhs.vertexIDs.1
            && lhs.vertexIDs.2 == rhs.vertexIDs.2
    }

    private enum CodingKeys: String, CodingKey {
        case faceID
        case vertexIDs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(faceID, forKey: .faceID)
        try container.encode([vertexIDs.0, vertexIDs.1, vertexIDs.2], forKey: .vertexIDs)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let vertices = try container.decode([MeshVertexID].self, forKey: .vertexIDs)
        guard vertices.count == 3 else {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh triangles must contain exactly three vertex IDs."
            )
        }
        faceID = try container.decode(MeshFaceID.self, forKey: .faceID)
        vertexIDs = (vertices[0], vertices[1], vertices[2])
    }
}
