import Foundation
import RupaCoreTypes

/// An immutable vertex-ID index bound to one MeshSource storage layout.
public struct MeshSourceTriangulationIndex: Sendable {
    let sourceIdentity: GeometrySourceID
    let vertexCount: Int
    private let sourceVertexStorageIdentity: GeometryBufferStorageIdentity
    private let vertexIndexByID: [MeshVertexID: Int]

    init(
        sourceIdentity: GeometrySourceID,
        vertexCount: Int,
        sourceVertexStorageIdentity: GeometryBufferStorageIdentity,
        vertexIndexByID: [MeshVertexID: Int]
    ) {
        self.sourceIdentity = sourceIdentity
        self.vertexCount = vertexCount
        self.sourceVertexStorageIdentity = sourceVertexStorageIdentity
        self.vertexIndexByID = vertexIndexByID
    }

    package func positionIndex(for vertexID: MeshVertexID) -> Int? {
        vertexIndexByID[vertexID]
    }

    func isCompatible(with source: MeshSource) -> Bool {
        source.identity == sourceIdentity
            && source.vertexIDs.count == vertexCount
            && source.vertexIDs.storageIdentityToken === sourceVertexStorageIdentity
    }
}
