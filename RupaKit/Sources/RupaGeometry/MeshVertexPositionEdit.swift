import Foundation
import RupaCoreTypes

/// A primitive position replacement addressed by a persistent vertex ID.
public struct MeshVertexPositionEdit: Codable, Equatable, Sendable {
    public let vertexID: MeshVertexID
    public let position: GeometryPoint3D

    public init(vertexID: MeshVertexID, position: GeometryPoint3D) throws {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            throw MeshEditError(
                code: .nonFiniteValue,
                message: "Primitive vertex positions must contain finite coordinates."
            )
        }
        self.vertexID = vertexID
        self.position = position
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let vertexID = try container.decode(MeshVertexID.self, forKey: .vertexID)
        let position = try container.decode(GeometryPoint3D.self, forKey: .position)
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            throw MeshEditError(
                code: .nonFiniteValue,
                message: "Primitive vertex positions must contain finite coordinates."
            )
        }
        try self.init(vertexID: vertexID, position: position)
    }

    private enum CodingKeys: String, CodingKey {
        case vertexID
        case position
    }
}
