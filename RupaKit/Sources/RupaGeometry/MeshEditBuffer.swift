import Foundation

public struct MeshEditBuffer: Sendable {
    private struct AddedFace: Sendable {
        var id: MeshFaceID
        var vertexIDs: [MeshVertexID]
    }

    private let source: MeshSource
    private let vertexIndexByID: [MeshVertexID: Int]
    private let faceIndexByID: [MeshFaceID: Int]
    private var vertexOverrides: [MeshVertexID: GeometryPoint3D] = [:]
    private var deletedFaceIDs: Set<MeshFaceID> = []
    private var addedFaces: [AddedFace] = []

    public init(source: MeshSource) {
        self.source = source
        self.vertexIndexByID = Dictionary(
            uniqueKeysWithValues: source.vertexIDs.enumerated().map { ($0.element, $0.offset) }
        )
        self.faceIndexByID = Dictionary(
            uniqueKeysWithValues: source.faceIDs.enumerated().map { ($0.element, $0.offset) }
        )
    }

    public var identity: MeshSourceID {
        source.identity
    }

    public var hasEdits: Bool {
        !vertexOverrides.isEmpty || !deletedFaceIDs.isEmpty || !addedFaces.isEmpty
    }

    public func position(for vertexID: MeshVertexID) throws -> GeometryPoint3D {
        guard let index = vertexIndexByID[vertexID] else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh edit references an unknown vertex."
            )
        }
        return vertexOverrides[vertexID] ?? source.vertexPositions[index]
    }

    public mutating func setVertexPosition(
        _ position: GeometryPoint3D,
        for vertexID: MeshVertexID
    ) throws {
        try position.validate()
        guard let index = vertexIndexByID[vertexID] else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh edit cannot move an unknown vertex."
            )
        }
        let original = source.vertexPositions[index]
        if position == original {
            vertexOverrides.removeValue(forKey: vertexID)
        } else {
            vertexOverrides[vertexID] = position
        }
    }

    public mutating func addFace(vertexIDs: [MeshVertexID]) throws -> MeshFaceID {
        guard vertexIDs.count >= 3,
              Set(vertexIDs).count == vertexIDs.count,
              vertexIDs.allSatisfy({ self.vertexIndexByID[$0] != nil }) else {
            throw MeshSourceError(
                code: .invalidFaceLoop,
                message: "Added mesh faces require three or more unique existing vertices."
            )
        }
        let id = MeshFaceID(
            try nextRawValue(
                after: source.faceIDs.map(\.rawValue) + addedFaces.map { $0.id.rawValue }
            )
        )
        addedFaces.append(AddedFace(id: id, vertexIDs: vertexIDs))
        return id
    }

    public mutating func deleteFace(_ faceID: MeshFaceID) throws {
        if let addedIndex = addedFaces.firstIndex(where: { $0.id == faceID }) {
            addedFaces.remove(at: addedIndex)
            return
        }
        guard faceIndexByID[faceID] != nil else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh edit cannot delete an unknown face."
            )
        }
        deletedFaceIDs.insert(faceID)
    }

    public func commit() throws -> MeshEditCommitResult {
        guard hasEdits else {
            return MeshEditCommitResult(
                source: source,
                telemetry: GeometryCopyTelemetry()
            )
        }
        if deletedFaceIDs.isEmpty && addedFaces.isEmpty {
            return try commitVertexEdits()
        }
        guard source.attributes.count == 0 else {
            throw MeshSourceError(
                code: .unsupportedOperation,
                message: "Topology edits require attribute remapping before commit."
            )
        }
        return try commitTopologyEdits()
    }

    private func commitVertexEdits() throws -> MeshEditCommitResult {
        var telemetry = GeometryCopyTelemetry()
        var positions = source.vertexPositions
        for (vertexID, position) in vertexOverrides {
            guard let index = source.vertexIDs.firstIndex(of: vertexID) else {
                throw MeshSourceError(
                    code: .invalidReference,
                    message: "Mesh edit cannot commit an unknown vertex."
                )
            }
            positions = try positions.replacingSubrange(
                index..<(index + 1),
                with: [position],
                telemetry: &telemetry
            )
        }
        return MeshEditCommitResult(
            source: try MeshSource(
                identity: source.identity,
                vertexIDs: source.vertexIDs,
                vertexPositions: positions,
                edgeIDs: source.edgeIDs,
                edgeEndpoints: source.edgeEndpoints,
                faceIDs: source.faceIDs,
                faceCornerRanges: source.faceCornerRanges,
                cornerIDs: source.cornerIDs,
                cornerVertexIDs: source.cornerVertexIDs,
                cornerEdgeIDs: source.cornerEdgeIDs,
                attributes: source.attributes
            ),
            telemetry: telemetry
        )
    }

    private func commitTopologyEdits() throws -> MeshEditCommitResult {
        var survivingFaces: [(MeshFaceID, [MeshVertexID])] = []
        survivingFaces.reserveCapacity(source.faceIDs.count + addedFaces.count)
        for faceID in source.faceIDs where !deletedFaceIDs.contains(faceID) {
            survivingFaces.append((faceID, try sourceVertexIDs(for: faceID)))
        }
        survivingFaces.append(contentsOf: addedFaces.map { ($0.id, $0.vertexIDs) })

        let vertexIDs = Array(source.vertexIDs)
        var positions = Array(source.vertexPositions)
        for index in vertexIDs.indices {
            if let override = vertexOverrides[vertexIDs[index]] {
                positions[index] = override
            }
        }
        var edgeIDs = Array(source.edgeIDs)
        var edgeEndpoints = Array(source.edgeEndpoints)
        var edgeByVertices: [EdgeKey: MeshEdgeID] = [:]
        for index in edgeIDs.indices {
            let endpoints = edgeEndpoints[index]
            edgeByVertices[EdgeKey(start: endpoints.start, end: endpoints.end)] = edgeIDs[index]
        }
        var faceIDs: [MeshFaceID] = []
        var faceCornerRanges: [MeshIndexRange] = []
        var cornerIDs: [MeshCornerID] = []
        var cornerVertexIDs: [MeshVertexID] = []
        var cornerEdgeIDs: [MeshEdgeID?] = []
        var nextCorner = try nextRawValue(after: source.cornerIDs.map(\.rawValue))
        var nextEdge = try nextRawValue(after: source.edgeIDs.map(\.rawValue))
        var telemetry = GeometryCopyTelemetry()

        for (faceID, loop) in survivingFaces {
            let start = cornerIDs.count
            let originalCorners: [MeshCornerID] = source.faceIDs.firstIndex(of: faceID).map { index in
                let range = source.faceCornerRanges[index]
                return Array(range.start..<range.end).map { source.cornerIDs[$0] }
            } ?? []
            for index in loop.indices {
                let vertexID = loop[index]
                let nextVertexID = loop[(index + 1) % loop.count]
                let edgeKey = EdgeKey(start: vertexID, end: nextVertexID)
                let edgeID: MeshEdgeID
                if let existing = edgeByVertices[edgeKey] {
                    edgeID = existing
                } else {
                    edgeID = MeshEdgeID(nextEdge)
                    nextEdge += 1
                    edgeIDs.append(edgeID)
                    edgeEndpoints.append(
                        MeshEdgeEndpoints(
                            start: min(vertexID, nextVertexID),
                            end: max(vertexID, nextVertexID)
                        )
                    )
                    edgeByVertices[edgeKey] = edgeID
                }
                let cornerID: MeshCornerID
                if index < originalCorners.count {
                    cornerID = originalCorners[index]
                } else {
                    cornerID = MeshCornerID(nextCorner)
                    nextCorner += 1
                }
                cornerIDs.append(cornerID)
                cornerVertexIDs.append(vertexID)
                cornerEdgeIDs.append(edgeID)
            }
            faceIDs.append(faceID)
            faceCornerRanges.append(MeshIndexRange(start: start, count: loop.count))
        }
        telemetry.record(
            reason: .sourceEdit,
            copiedBytes: vertexIDs.count * MemoryLayout<MeshVertexID>.stride
                + positions.count * MemoryLayout<GeometryPoint3D>.stride
                + edgeIDs.count * MemoryLayout<MeshEdgeID>.stride
                + edgeEndpoints.count * MemoryLayout<MeshEdgeEndpoints>.stride
                + faceIDs.count * MemoryLayout<MeshFaceID>.stride
                + faceCornerRanges.count * MemoryLayout<MeshIndexRange>.stride
                + cornerIDs.count * MemoryLayout<MeshCornerID>.stride
                + cornerVertexIDs.count * MemoryLayout<MeshVertexID>.stride
        )
        return MeshEditCommitResult(
            source: try MeshSource(
                identity: source.identity,
                vertexIDs: GeometryBuffer(vertexIDs),
                vertexPositions: GeometryBuffer(positions),
                edgeIDs: GeometryBuffer(edgeIDs),
                edgeEndpoints: GeometryBuffer(edgeEndpoints),
                faceIDs: GeometryBuffer(faceIDs),
                faceCornerRanges: GeometryBuffer(faceCornerRanges),
                cornerIDs: GeometryBuffer(cornerIDs),
                cornerVertexIDs: GeometryBuffer(cornerVertexIDs),
                cornerEdgeIDs: GeometryBuffer(cornerEdgeIDs)
            ),
            telemetry: telemetry
        )
    }

    private func sourceVertexIDs(for faceID: MeshFaceID) throws -> [MeshVertexID] {
        guard let index = faceIndexByID[faceID] else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh face is not present in the source."
            )
        }
        let range = source.faceCornerRanges[index]
        return Array(range.start..<range.end).map { source.cornerVertexIDs[$0] }
    }

    private func nextRawValue(after values: [UInt64]) throws -> UInt64 {
        guard let maximum = values.max() else {
            return 0
        }
        guard maximum < UInt64.max else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh edit ID space is exhausted."
            )
        }
        return maximum + 1
    }
}

private struct EdgeKey: Hashable, Sendable {
    let start: MeshVertexID
    let end: MeshVertexID

    init(start: MeshVertexID, end: MeshVertexID) {
        self.start = min(start, end)
        self.end = max(start, end)
    }
}
