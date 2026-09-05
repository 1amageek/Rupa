import Foundation
import RupaCoreTypes

/// The resources one materialized `MeshSource` accounts for.
///
/// `RupaGeometry` owns this model because only the geometry module knows how a
/// mesh stores its elements and its attribute layers. `byteCount` estimates the
/// resident footprint of the buffers the mesh holds, not a serialized size, so a
/// budget charged with it bounds memory the process has actually committed.
public struct MeshResourceUsage: Equatable, Hashable, Sendable {
    public var vertexCount: Int
    public var edgeCount: Int
    public var faceCount: Int
    public var cornerCount: Int
    public var triangleCount: Int
    public var byteCount: Int

    public init(
        vertexCount: Int,
        edgeCount: Int,
        faceCount: Int,
        cornerCount: Int,
        triangleCount: Int,
        byteCount: Int
    ) {
        self.vertexCount = vertexCount
        self.edgeCount = edgeCount
        self.faceCount = faceCount
        self.cornerCount = cornerCount
        self.triangleCount = triangleCount
        self.byteCount = byteCount
    }

    public static let zero = MeshResourceUsage(
        vertexCount: 0,
        edgeCount: 0,
        faceCount: 0,
        cornerCount: 0,
        triangleCount: 0,
        byteCount: 0
    )

    /// Adds another mesh's usage, refusing a total no process could hold.
    public func adding(_ other: MeshResourceUsage) throws -> MeshResourceUsage {
        MeshResourceUsage(
            vertexCount: try Self.sum(vertexCount, other.vertexCount),
            edgeCount: try Self.sum(edgeCount, other.edgeCount),
            faceCount: try Self.sum(faceCount, other.faceCount),
            cornerCount: try Self.sum(cornerCount, other.cornerCount),
            triangleCount: try Self.sum(triangleCount, other.triangleCount),
            byteCount: try Self.sum(byteCount, other.byteCount)
        )
    }

    static func sum(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh resource usage exceeded the representable range."
            )
        }
        return result.partialValue
    }

    static func product(_ count: Int, _ stride: Int) throws -> Int {
        let result = count.multipliedReportingOverflow(by: stride)
        guard !result.overflow else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh resource usage exceeded the representable range."
            )
        }
        return result.partialValue
    }
}

extension MeshSource {
    /// The resources this mesh accounts for.
    ///
    /// Element counts are read from the buffers themselves. `triangleCount` is
    /// the fan triangulation every consumer of a polygonal face performs, so a
    /// face of `n` corners contributes `n - 2`. Bytes are the sum of every
    /// element buffer and every attribute layer, because attribute storage is
    /// resident for as long as the mesh is.
    public func resourceUsage() throws -> MeshResourceUsage {
        var triangleCount = 0
        for range in faceCornerRanges {
            guard range.count >= 3 else {
                throw MeshSourceError(
                    code: .invalidFaceLoop,
                    message: "Mesh faces must have at least three corners to be triangulated."
                )
            }
            triangleCount = try MeshResourceUsage.sum(triangleCount, range.count - 2)
        }

        var byteCount = 0
        for bytes in [
            try MeshResourceUsage.product(vertexIDs.count, MemoryLayout<MeshVertexID>.stride),
            try MeshResourceUsage.product(
                vertexPositions.count,
                MemoryLayout<GeometryPoint3D>.stride
            ),
            try MeshResourceUsage.product(edgeIDs.count, MemoryLayout<MeshEdgeID>.stride),
            try MeshResourceUsage.product(
                edgeEndpoints.count,
                MemoryLayout<MeshEdgeEndpoints>.stride
            ),
            try MeshResourceUsage.product(faceIDs.count, MemoryLayout<MeshFaceID>.stride),
            try MeshResourceUsage.product(
                faceCornerRanges.count,
                MemoryLayout<MeshIndexRange>.stride
            ),
            try MeshResourceUsage.product(cornerIDs.count, MemoryLayout<MeshCornerID>.stride),
            try MeshResourceUsage.product(
                cornerVertexIDs.count,
                MemoryLayout<MeshVertexID>.stride
            ),
            try MeshResourceUsage.product(cornerEdgeIDs.count, MemoryLayout<MeshEdgeID>.stride),
            try attributes.estimatedByteCount(),
        ] {
            byteCount = try MeshResourceUsage.sum(byteCount, bytes)
        }

        return MeshResourceUsage(
            vertexCount: vertexIDs.count,
            edgeCount: edgeIDs.count,
            faceCount: faceIDs.count,
            cornerCount: cornerIDs.count,
            triangleCount: triangleCount,
            byteCount: byteCount
        )
    }
}
