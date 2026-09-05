import Foundation
import RupaCoreTypes

/// An immutable vertex-ID index bound to one MeshSource storage layout.
public struct MeshSourceTriangulationIndex: Sendable {
    /// Conservative scratch admission for the native Dictionary used below.
    /// Two buckets per entry, rounded to a power of two, leave room for its
    /// load factor; 32 bytes per bucket include key, value, occupancy and
    /// alignment. This is an upper-bound reservation, not measured RSS.
    public static func storageReservation(vertexCount: Int) throws -> Int {
        guard vertexCount >= 0 else {
            throw MeshTriangulationError(code: .sizeOverflow, message: "Negative vertex count.")
        }
        guard vertexCount > 0 else { return 0 }
        let requested = vertexCount.multipliedReportingOverflow(by: 2)
        guard !requested.overflow else {
            throw MeshTriangulationError(code: .sizeOverflow, message: "Index size overflow.")
        }
        var buckets = 2
        while buckets < requested.partialValue {
            let next = buckets.multipliedReportingOverflow(by: 2)
            guard !next.overflow else {
                throw MeshTriangulationError(code: .sizeOverflow, message: "Index size overflow.")
            }
            buckets = next.partialValue
        }
        let bytes = buckets.multipliedReportingOverflow(by: 32)
        let total = bytes.partialValue.addingReportingOverflow(128)
        guard !bytes.overflow, !total.overflow else {
            throw MeshTriangulationError(code: .sizeOverflow, message: "Index size overflow.")
        }
        return total.partialValue
    }

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
