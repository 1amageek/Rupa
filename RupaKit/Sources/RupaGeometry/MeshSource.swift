import Foundation

public struct MeshSource: Codable, Equatable, Sendable {
    public let identity: MeshSourceID
    public let vertexIDs: GeometryBuffer<MeshVertexID>
    public let vertexPositions: GeometryBuffer<GeometryPoint3D>
    public let edgeIDs: GeometryBuffer<MeshEdgeID>
    public let edgeEndpoints: GeometryBuffer<MeshEdgeEndpoints>
    public let faceIDs: GeometryBuffer<MeshFaceID>
    public let faceCornerRanges: GeometryBuffer<MeshIndexRange>
    public let cornerIDs: GeometryBuffer<MeshCornerID>
    public let cornerVertexIDs: GeometryBuffer<MeshVertexID>
    public let cornerEdgeIDs: GeometryBuffer<MeshEdgeID?>

    public init(
        identity: MeshSourceID = MeshSourceID(),
        vertexIDs: GeometryBuffer<MeshVertexID>,
        vertexPositions: GeometryBuffer<GeometryPoint3D>,
        edgeIDs: GeometryBuffer<MeshEdgeID>,
        edgeEndpoints: GeometryBuffer<MeshEdgeEndpoints>,
        faceIDs: GeometryBuffer<MeshFaceID>,
        faceCornerRanges: GeometryBuffer<MeshIndexRange>,
        cornerIDs: GeometryBuffer<MeshCornerID>,
        cornerVertexIDs: GeometryBuffer<MeshVertexID>,
        cornerEdgeIDs: GeometryBuffer<MeshEdgeID?>
    ) throws {
        self.identity = identity
        self.vertexIDs = vertexIDs
        self.vertexPositions = vertexPositions
        self.edgeIDs = edgeIDs
        self.edgeEndpoints = edgeEndpoints
        self.faceIDs = faceIDs
        self.faceCornerRanges = faceCornerRanges
        self.cornerIDs = cornerIDs
        self.cornerVertexIDs = cornerVertexIDs
        self.cornerEdgeIDs = cornerEdgeIDs
        try validate()
    }

    public func validate() throws {
        try identity.validate()
        guard vertexIDs.count == vertexPositions.count else {
            throw invalid("Vertex ID and position buffers must have equal counts.")
        }
        guard edgeIDs.count == edgeEndpoints.count else {
            throw invalid("Edge ID and endpoint buffers must have equal counts.")
        }
        guard faceIDs.count == faceCornerRanges.count else {
            throw invalid("Face ID and corner range buffers must have equal counts.")
        }
        guard cornerIDs.count == cornerVertexIDs.count,
              cornerIDs.count == cornerEdgeIDs.count else {
            throw invalid("Corner buffers must have equal counts.")
        }

        try validateUnique(vertexIDs, label: "vertex")
        try validateUnique(edgeIDs, label: "edge")
        try validateUnique(faceIDs, label: "face")
        try validateUnique(cornerIDs, label: "corner")
        for position in vertexPositions {
            try position.validate()
        }

        let vertexSet = Set(vertexIDs)
        let edgeSet = Set(edgeIDs)
        for endpoints in edgeEndpoints {
            guard endpoints.start != endpoints.end,
                  vertexSet.contains(endpoints.start),
                  vertexSet.contains(endpoints.end) else {
                throw invalid("Edges must reference two distinct existing vertices.")
            }
        }
        for edgeID in cornerEdgeIDs.compactMap({ $0 }) {
            guard edgeSet.contains(edgeID) else {
                throw invalid("Corners must reference existing edges when an edge is present.")
            }
        }
        for vertexID in cornerVertexIDs {
            guard vertexSet.contains(vertexID) else {
                throw invalid("Corners must reference existing vertices.")
            }
        }
        for faceRange in faceCornerRanges {
            try faceRange.validate(upperBound: cornerIDs.count)
            guard faceRange.count >= 3 else {
                throw invalid("Faces must contain at least three corners.")
            }
        }
    }

    public func faceLoop(for faceID: MeshFaceID) throws -> MeshFaceLoop {
        guard let index = faceIDs.firstIndex(of: faceID) else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh face \(faceID.rawValue) is not present in the source."
            )
        }
        let range = faceCornerRanges[index]
        let view = try cornerIDs.view(range.start..<range.end)
        return MeshFaceLoop(faceID: faceID, cornerView: view)
    }

    public func position(of vertexID: MeshVertexID) throws -> GeometryPoint3D {
        guard let index = vertexIDs.firstIndex(of: vertexID) else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh vertex \(vertexID.rawValue) is not present in the source."
            )
        }
        return vertexPositions[index]
    }

    private func validateUnique<Element: Hashable>(
        _ values: GeometryBuffer<Element>,
        label: String
    ) throws {
        guard Set(values).count == values.count else {
            throw MeshSourceError(
                code: .duplicateID,
                message: "Mesh \(label) IDs must be unique."
            )
        }
    }

    private func invalid(_ message: String) -> MeshSourceError {
        MeshSourceError(code: .invalidBuffer, message: message)
    }
}
