import Foundation

public struct MeshSourceBuilder: Sendable {
    private var identity: MeshSourceID
    private var vertexIDs: [MeshVertexID] = []
    private var vertexPositions: [GeometryPoint3D] = []
    private var edgeIDs: [MeshEdgeID] = []
    private var edgeEndpoints: [MeshEdgeEndpoints] = []
    private var faceIDs: [MeshFaceID] = []
    private var faceCornerRanges: [MeshIndexRange] = []
    private var cornerIDs: [MeshCornerID] = []
    private var cornerVertexIDs: [MeshVertexID] = []
    private var cornerEdgeIDs: [MeshEdgeID?] = []
    private var edgeByVertices: [MeshUndirectedEdgeKey: MeshEdgeID] = [:]

    public init(identity: MeshSourceID = MeshSourceID()) {
        self.identity = identity
    }

    public mutating func addVertex(_ position: GeometryPoint3D) throws -> MeshVertexID {
        try position.validate()
        let id = MeshVertexID(UInt64(vertexIDs.count))
        vertexIDs.append(id)
        vertexPositions.append(position)
        return id
    }

    public mutating func addFace(vertexIDs faceVertexIDs: [MeshVertexID]) throws -> MeshFaceID {
        guard faceVertexIDs.count >= 3,
              Set(faceVertexIDs).count == faceVertexIDs.count else {
            throw MeshSourceError(
                code: .invalidFaceLoop,
                message: "Mesh faces require at least three unique vertices."
            )
        }
        let knownVertices = Set(vertexIDs)
        guard faceVertexIDs.allSatisfy({ knownVertices.contains($0) }) else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh faces must reference vertices already added to the source."
            )
        }

        let faceID = MeshFaceID(UInt64(faceIDs.count))
        let start = cornerIDs.count
        for index in faceVertexIDs.indices {
            let vertexID = faceVertexIDs[index]
            let nextVertexID = faceVertexIDs[(index + 1) % faceVertexIDs.count]
            let edgeID = edgeID(for: vertexID, and: nextVertexID)
            cornerIDs.append(MeshCornerID(UInt64(cornerIDs.count)))
            cornerVertexIDs.append(vertexID)
            cornerEdgeIDs.append(edgeID)
        }
        faceIDs.append(faceID)
        faceCornerRanges.append(
            MeshIndexRange(start: start, count: faceVertexIDs.count)
        )
        return faceID
    }

    public func build() throws -> MeshSource {
        try MeshSource(
            identity: identity,
            vertexIDs: GeometryBuffer(vertexIDs),
            vertexPositions: GeometryBuffer(vertexPositions),
            edgeIDs: GeometryBuffer(edgeIDs),
            edgeEndpoints: GeometryBuffer(edgeEndpoints),
            faceIDs: GeometryBuffer(faceIDs),
            faceCornerRanges: GeometryBuffer(faceCornerRanges),
            cornerIDs: GeometryBuffer(cornerIDs),
            cornerVertexIDs: GeometryBuffer(cornerVertexIDs),
            cornerEdgeIDs: GeometryBuffer(cornerEdgeIDs)
        )
    }

    private mutating func edgeID(
        for first: MeshVertexID,
        and second: MeshVertexID
    ) -> MeshEdgeID {
        let key = MeshUndirectedEdgeKey(first: first, second: second)
        if let existing = edgeByVertices[key] {
            return existing
        }
        let id = MeshEdgeID(UInt64(edgeIDs.count))
        edgeIDs.append(id)
        edgeEndpoints.append(
            MeshEdgeEndpoints(
                start: min(first, second),
                end: max(first, second)
            )
        )
        edgeByVertices[key] = id
        return id
    }
}

private struct MeshUndirectedEdgeKey: Hashable, Sendable {
    let first: MeshVertexID
    let second: MeshVertexID

    init(first: MeshVertexID, second: MeshVertexID) {
        self.first = min(first, second)
        self.second = max(first, second)
    }
}
