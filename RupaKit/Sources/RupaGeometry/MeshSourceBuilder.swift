import Foundation
import RupaCoreTypes

/// Single-owner construction of a compact immutable mesh source.
public struct MeshSourceBuilder: ~Copyable, Sendable {
    private let identity: GeometrySourceID
    private var allocationState: MeshElementIDAllocationState
    private var vertexIDs = GeometryBufferConstructionBuffer<MeshVertexID>()
    private var vertexPositions = GeometryBufferConstructionBuffer<GeometryPoint3D>()
    private var edgeIDs = GeometryBufferConstructionBuffer<MeshEdgeID>()
    private var edgeEndpoints = GeometryBufferConstructionBuffer<MeshEdgeEndpoints>()
    private var faceIDs = GeometryBufferConstructionBuffer<MeshFaceID>()
    private var faceCornerRanges = GeometryBufferConstructionBuffer<MeshIndexRange>()
    private var cornerIDs = GeometryBufferConstructionBuffer<MeshCornerID>()
    private var cornerVertexIDs = GeometryBufferConstructionBuffer<MeshVertexID>()
    private var cornerEdgeIDs = GeometryBufferConstructionBuffer<MeshEdgeID>()
    private var attributes = GeometryAttributeSet()
    private var vertexIDSet: Set<MeshVertexID> = []
    private var edgeByVertices: [MeshUndirectedEdgeKey: MeshEdgeID] = [:]

    public init(identity: GeometrySourceID = GeometrySourceID()) {
        self.identity = identity
        self.allocationState = MeshElementIDAllocationState()
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
        vertexIDSet.reserveCapacity(vertexCount)
        edgeByVertices.reserveCapacity(cornerCount)
    }

    public mutating func addVertex(_ position: GeometryPoint3D) throws -> MeshVertexID {
        try position.validate()
        try allocationState.validateVertexAllocation(count: 1)
        try vertexIDs.validateAppending(1)
        try vertexPositions.validateAppending(1)
        let id = try allocationState.allocateVertexID()
        try vertexIDs.append(id)
        try vertexPositions.append(position)
        vertexIDSet.insert(id)
        return id
    }

    /// Adds a loose edge or returns the existing edge for the same undirected endpoints.
    public mutating func addEdge(
        _ first: MeshVertexID,
        _ second: MeshVertexID
    ) throws -> MeshEdgeID {
        guard first != second,
              containsVertex(first),
              containsVertex(second) else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh edges require two distinct vertices already added to the source."
            )
        }
        let key = MeshUndirectedEdgeKey(first: first, second: second)
        if let existing = edgeByVertices[key] {
            return existing
        }
        try allocationState.validateEdgeAllocation(count: 1)
        try edgeIDs.validateAppending(1)
        try edgeEndpoints.validateAppending(1)
        return try edgeID(for: first, and: second)
    }

    public mutating func addFace<Vertices: Collection>(
        vertexIDs faceVertexIDs: Vertices
    ) throws -> MeshFaceID where Vertices.Element == MeshVertexID {
        guard faceVertexIDs.count >= 3 else {
            throw MeshSourceError(
                code: .invalidFaceLoop,
                message: "Mesh faces require at least three unique vertices."
            )
        }
        var uniqueVertexIDs: Set<MeshVertexID> = []
        uniqueVertexIDs.reserveCapacity(faceVertexIDs.count)
        for vertexID in faceVertexIDs {
            guard uniqueVertexIDs.insert(vertexID).inserted else {
                throw MeshSourceError(
                    code: .invalidFaceLoop,
                    message: "Mesh faces require at least three unique vertices."
                )
            }
            guard containsVertex(vertexID) else {
                throw MeshSourceError(
                    code: .invalidReference,
                    message: "Mesh faces must reference vertices already added to the source."
                )
            }
        }

        var missingEdgeKeys: Set<MeshUndirectedEdgeKey> = []
        missingEdgeKeys.reserveCapacity(faceVertexIDs.count)
        guard let firstVertexID = faceVertexIDs.first else {
            throw MeshSourceError(
                code: .invalidFaceLoop,
                message: "Mesh faces require at least three vertices."
            )
        }
        var currentVertexID = firstVertexID
        for nextVertexID in faceVertexIDs.dropFirst() {
            let key = MeshUndirectedEdgeKey(first: currentVertexID, second: nextVertexID)
            if edgeByVertices[key] == nil {
                missingEdgeKeys.insert(key)
            }
            currentVertexID = nextVertexID
        }
        let closingKey = MeshUndirectedEdgeKey(first: currentVertexID, second: firstVertexID)
        if edgeByVertices[closingKey] == nil {
            missingEdgeKeys.insert(closingKey)
        }
        try validateFaceAppend(
            cornerCount: faceVertexIDs.count,
            newEdgeCount: missingEdgeKeys.count
        )

        let faceID = try allocationState.allocateFaceID()
        let start = cornerIDs.count
        currentVertexID = firstVertexID
        for nextVertexID in faceVertexIDs.dropFirst() {
            try appendCorner(vertexID: currentVertexID, nextVertexID: nextVertexID)
            currentVertexID = nextVertexID
        }
        try appendCorner(vertexID: currentVertexID, nextVertexID: firstVertexID)
        try faceIDs.append(faceID)
        try faceCornerRanges.append(
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
        let firstEdgeKey = MeshUndirectedEdgeKey(first: first, second: second)
        let secondEdgeKey = MeshUndirectedEdgeKey(first: second, second: third)
        let thirdEdgeKey = MeshUndirectedEdgeKey(first: third, second: first)
        var missingEdgeCount = 0
        if edgeByVertices[firstEdgeKey] == nil {
            missingEdgeCount += 1
        }
        if edgeByVertices[secondEdgeKey] == nil {
            missingEdgeCount += 1
        }
        if edgeByVertices[thirdEdgeKey] == nil {
            missingEdgeCount += 1
        }
        try validateFaceAppend(cornerCount: 3, newEdgeCount: missingEdgeCount)

        let faceID = try allocationState.allocateFaceID()
        let start = cornerIDs.count
        try appendCorner(vertexID: first, nextVertexID: second)
        try appendCorner(vertexID: second, nextVertexID: third)
        try appendCorner(vertexID: third, nextVertexID: first)
        try faceIDs.append(faceID)
        try faceCornerRanges.append(MeshIndexRange(start: start, count: 3))
        return faceID
    }

    public mutating func setAttribute(_ layer: GeometryAttributeLayer) throws {
        attributes = try attributes.setting(layer)
    }

    public consuming func build() throws -> MeshSource {
        try makeSource()
    }

    public consuming func build(
        telemetry: inout GeometryCopyTelemetry
    ) throws -> MeshSource {
        let source = try makeSource()
        try vertexIDs.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        try vertexPositions.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        try edgeIDs.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        try edgeEndpoints.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        try faceIDs.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        try faceCornerRanges.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        try cornerIDs.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        try cornerVertexIDs.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        try cornerEdgeIDs.recordCopy(reason: .bufferMaterialization, in: &telemetry)
        return source
    }

    private borrowing func makeSource() throws -> MeshSource {
        try MeshSource(
            identity: identity,
            allocationState: allocationState,
            vertexIDs: vertexIDs.build(),
            vertexPositions: vertexPositions.build(),
            edgeIDs: edgeIDs.build(),
            edgeEndpoints: edgeEndpoints.build(),
            faceIDs: faceIDs.build(),
            faceCornerRanges: faceCornerRanges.build(),
            cornerIDs: cornerIDs.build(),
            cornerVertexIDs: cornerVertexIDs.build(),
            cornerEdgeIDs: cornerEdgeIDs.build(),
            attributes: attributes
        )
    }

    private func containsVertex(_ vertexID: MeshVertexID) -> Bool {
        vertexIDSet.contains(vertexID)
    }

    private func validateFaceAppend(
        cornerCount: Int,
        newEdgeCount: Int
    ) throws {
        try allocationState.validateFaceAllocation(count: 1)
        try allocationState.validateCornerAllocation(count: cornerCount)
        try allocationState.validateEdgeAllocation(count: newEdgeCount)
        try faceIDs.validateAppending(1)
        try faceCornerRanges.validateAppending(1)
        try cornerIDs.validateAppending(cornerCount)
        try cornerVertexIDs.validateAppending(cornerCount)
        try cornerEdgeIDs.validateAppending(cornerCount)
        try edgeIDs.validateAppending(newEdgeCount)
        try edgeEndpoints.validateAppending(newEdgeCount)
    }

    private mutating func appendCorner(
        vertexID: MeshVertexID,
        nextVertexID: MeshVertexID
    ) throws {
        let edgeID = try edgeID(for: vertexID, and: nextVertexID)
        try cornerIDs.append(allocationState.allocateCornerID())
        try cornerVertexIDs.append(vertexID)
        try cornerEdgeIDs.append(edgeID)
    }

    private mutating func edgeID(
        for first: MeshVertexID,
        and second: MeshVertexID
    ) throws -> MeshEdgeID {
        let key = MeshUndirectedEdgeKey(first: first, second: second)
        if let existing = edgeByVertices[key] {
            return existing
        }
        let id = try allocationState.allocateEdgeID()
        try edgeIDs.append(id)
        try edgeEndpoints.append(
            MeshEdgeEndpoints(start: key.first, end: key.second)
        )
        edgeByVertices[key] = id
        return id
    }
}
