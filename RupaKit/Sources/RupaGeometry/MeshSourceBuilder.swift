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
    private var attributes = GeometryAttributeSet()
    private var edgeByVertices: [MeshUndirectedEdgeKey: MeshEdgeID] = [:]

    public init(identity: MeshSourceID = MeshSourceID()) {
        self.identity = identity
    }

    public mutating func reserveCapacity(
        vertexCount: Int,
        faceCount: Int,
        cornerCount: Int
    ) throws {
        guard vertexCount >= 0,
              faceCount >= 0,
              cornerCount >= 0 else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh capacity estimates cannot be negative."
            )
        }
        vertexIDs.reserveCapacity(vertexCount)
        vertexPositions.reserveCapacity(vertexCount)
        edgeIDs.reserveCapacity(cornerCount)
        edgeEndpoints.reserveCapacity(cornerCount)
        faceIDs.reserveCapacity(faceCount)
        faceCornerRanges.reserveCapacity(faceCount)
        cornerIDs.reserveCapacity(cornerCount)
        cornerVertexIDs.reserveCapacity(cornerCount)
        cornerEdgeIDs.reserveCapacity(cornerCount)
        edgeByVertices.reserveCapacity(cornerCount)
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
        guard faceVertexIDs.allSatisfy(containsVertex) else {
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
            appendCorner(vertexID: vertexID, nextVertexID: nextVertexID)
        }
        faceIDs.append(faceID)
        faceCornerRanges.append(
            MeshIndexRange(start: start, count: faceVertexIDs.count)
        )
        return faceID
    }

    public mutating func addTriangle(
        _ first: MeshVertexID,
        _ second: MeshVertexID,
        _ third: MeshVertexID
    ) throws -> MeshFaceID {
        guard first != second,
              second != third,
              third != first else {
            throw MeshSourceError(
                code: .invalidFaceLoop,
                message: "Mesh triangles require three unique vertices."
            )
        }
        guard containsVertex(first),
              containsVertex(second),
              containsVertex(third) else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh triangles must reference vertices already added to the source."
            )
        }

        let faceID = MeshFaceID(UInt64(faceIDs.count))
        let start = cornerIDs.count
        appendCorner(vertexID: first, nextVertexID: second)
        appendCorner(vertexID: second, nextVertexID: third)
        appendCorner(vertexID: third, nextVertexID: first)
        faceIDs.append(faceID)
        faceCornerRanges.append(MeshIndexRange(start: start, count: 3))
        return faceID
    }

    public mutating func setAttribute(_ layer: GeometryAttributeLayer) throws {
        attributes = try attributes.setting(layer)
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
            cornerEdgeIDs: GeometryBuffer(cornerEdgeIDs),
            attributes: attributes
        )
    }

    private func containsVertex(_ vertexID: MeshVertexID) -> Bool {
        guard let index = Int(exactly: vertexID.rawValue),
              vertexIDs.indices.contains(index) else {
            return false
        }
        return vertexIDs[index] == vertexID
    }

    private mutating func appendCorner(
        vertexID: MeshVertexID,
        nextVertexID: MeshVertexID
    ) {
        let edgeID = edgeID(for: vertexID, and: nextVertexID)
        cornerIDs.append(MeshCornerID(UInt64(cornerIDs.count)))
        cornerVertexIDs.append(vertexID)
        cornerEdgeIDs.append(edgeID)
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
