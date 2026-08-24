import Foundation
import RupaCoreTypes

public struct MeshEditBuffer: Sendable {
    private struct AddedFace: Sendable {
        var id: MeshFaceID
        var vertexIDs: [MeshVertexID]
    }

    private let source: MeshSource
    private let vertexIndexByID: [MeshVertexID: Int]
    private let faceIndexByID: [MeshFaceID: Int]
    private var allocationState: MeshElementIDAllocationState
    private var vertexOverrides: [MeshVertexID: GeometryPoint3D] = [:]
    private var deletedFaceIDs: Set<MeshFaceID> = []
    private var addedFaces: [AddedFace] = []

    public init(source: MeshSource) {
        self.source = source
        var vertexIndexByID: [MeshVertexID: Int] = [:]
        vertexIndexByID.reserveCapacity(source.vertexIDs.count)
        for index in source.vertexIDs.indices {
            vertexIndexByID[source.vertexIDs[index]] = index
        }
        self.vertexIndexByID = vertexIndexByID
        var faceIndexByID: [MeshFaceID: Int] = [:]
        faceIndexByID.reserveCapacity(source.faceIDs.count)
        for index in source.faceIDs.indices {
            faceIndexByID[source.faceIDs[index]] = index
        }
        self.faceIndexByID = faceIndexByID
        self.allocationState = source.allocationState
    }

    public var identity: GeometrySourceID {
        source.identity
    }

    public var hasEdits: Bool {
        !vertexOverrides.isEmpty
            || !deletedFaceIDs.isEmpty
            || !addedFaces.isEmpty
            || allocationState != source.allocationState
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
        let id = try allocationState.allocateFaceID()
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
        var positions = source.vertexPositions.makeBuilder()
        for (vertexID, position) in vertexOverrides {
            guard let index = vertexIndexByID[vertexID] else {
                throw MeshSourceError(
                    code: .invalidReference,
                    message: "Mesh edit cannot commit an unknown vertex."
                )
            }
            try positions.replaceSubrange(
                index..<(index + 1),
                with: CollectionOfOne(position)
            )
        }
        let editedPositions = positions.build()
        return MeshEditCommitResult(
            source: try MeshSource(
                identity: source.identity,
                allocationState: allocationState,
                vertexIDs: source.vertexIDs,
                vertexPositions: editedPositions,
                edgeIDs: source.edgeIDs,
                edgeEndpoints: source.edgeEndpoints,
                faceIDs: source.faceIDs,
                faceCornerRanges: source.faceCornerRanges,
                cornerIDs: source.cornerIDs,
                cornerVertexIDs: source.cornerVertexIDs,
                cornerEdgeIDs: source.cornerEdgeIDs,
                attributes: source.attributes
            ),
            telemetry: positions.telemetry
        )
    }

    private func commitTopologyEdits() throws -> MeshEditCommitResult {
        var allocationState = self.allocationState
        var positions = source.vertexPositions.makeBuilder()
        for (vertexID, position) in vertexOverrides {
            guard let index = vertexIndexByID[vertexID] else {
                throw MeshSourceError(
                    code: .invalidReference,
                    message: "Mesh edit cannot commit an unknown vertex."
                )
            }
            try positions.replaceSubrange(
                index..<(index + 1),
                with: CollectionOfOne(position)
            )
        }
        let editedPositions = positions.build()

        var edgeIDs = source.edgeIDs.makeBuilder()
        var edgeEndpoints = source.edgeEndpoints.makeBuilder()
        var edgeByVertices: [MeshUndirectedEdgeKey: MeshEdgeID] = [:]
        edgeByVertices.reserveCapacity(source.edgeIDs.count)
        for index in source.edgeIDs.indices {
            let endpoints = source.edgeEndpoints[index]
            edgeByVertices[
                MeshUndirectedEdgeKey(first: endpoints.start, second: endpoints.end)
            ] = source.edgeIDs[index]
        }
        var faceIDs = GeometryBufferConstructionBuffer<MeshFaceID>()
        var faceCornerRanges = GeometryBufferConstructionBuffer<MeshIndexRange>()
        var cornerIDs = GeometryBufferConstructionBuffer<MeshCornerID>()
        var cornerVertexIDs = GeometryBufferConstructionBuffer<MeshVertexID>()
        var cornerEdgeIDs = GeometryBufferConstructionBuffer<MeshEdgeID>()
        faceIDs.reserveCapacity(source.faceIDs.count + addedFaces.count)
        faceCornerRanges.reserveCapacity(source.faceIDs.count + addedFaces.count)
        cornerIDs.reserveCapacity(source.cornerIDs.count)
        cornerVertexIDs.reserveCapacity(source.cornerIDs.count)
        cornerEdgeIDs.reserveCapacity(source.cornerIDs.count)
        var telemetry = GeometryCopyTelemetry()

        for faceIndex in source.faceIDs.indices {
            let faceID = source.faceIDs[faceIndex]
            guard !deletedFaceIDs.contains(faceID) else {
                continue
            }
            let start = cornerIDs.count
            let range = source.faceCornerRanges[faceIndex]
            for cornerIndex in range.start..<range.end {
                try cornerIDs.append(source.cornerIDs[cornerIndex])
                try cornerVertexIDs.append(source.cornerVertexIDs[cornerIndex])
                try cornerEdgeIDs.append(source.cornerEdgeIDs[cornerIndex])
            }
            try faceIDs.append(faceID)
            try faceCornerRanges.append(
                MeshIndexRange(start: start, count: range.count)
            )
        }

        for addedFace in addedFaces {
            let start = cornerIDs.count
            for index in addedFace.vertexIDs.indices {
                let vertexID = addedFace.vertexIDs[index]
                let nextVertexID = addedFace.vertexIDs[
                    (index + 1) % addedFace.vertexIDs.count
                ]
                let edgeKey = MeshUndirectedEdgeKey(
                    first: vertexID,
                    second: nextVertexID
                )
                let edgeID: MeshEdgeID
                if let existing = edgeByVertices[edgeKey] {
                    edgeID = existing
                } else {
                    edgeID = try allocationState.allocateEdgeID()
                    try edgeIDs.append(edgeID)
                    try edgeEndpoints.append(
                        MeshEdgeEndpoints(
                            start: edgeKey.first,
                            end: edgeKey.second
                        )
                    )
                    edgeByVertices[edgeKey] = edgeID
                }
                try cornerIDs.append(allocationState.allocateCornerID())
                try cornerVertexIDs.append(vertexID)
                try cornerEdgeIDs.append(edgeID)
            }
            try faceIDs.append(addedFace.id)
            try faceCornerRanges.append(
                MeshIndexRange(start: start, count: addedFace.vertexIDs.count)
            )
        }
        try telemetry.record(contentsOf: positions.telemetry)
        try telemetry.record(contentsOf: edgeIDs.telemetry)
        try telemetry.record(contentsOf: edgeEndpoints.telemetry)
        try faceIDs.recordCopy(reason: .sourceEdit, in: &telemetry)
        try faceCornerRanges.recordCopy(reason: .sourceEdit, in: &telemetry)
        try cornerIDs.recordCopy(reason: .sourceEdit, in: &telemetry)
        try cornerVertexIDs.recordCopy(reason: .sourceEdit, in: &telemetry)
        try cornerEdgeIDs.recordCopy(reason: .sourceEdit, in: &telemetry)
        let editedEdgeIDs = edgeIDs.build()
        let editedEdgeEndpoints = edgeEndpoints.build()
        return MeshEditCommitResult(
            source: try MeshSource(
                identity: source.identity,
                allocationState: allocationState,
                vertexIDs: source.vertexIDs,
                vertexPositions: editedPositions,
                edgeIDs: editedEdgeIDs,
                edgeEndpoints: editedEdgeEndpoints,
                faceIDs: faceIDs.build(),
                faceCornerRanges: faceCornerRanges.build(),
                cornerIDs: cornerIDs.build(),
                cornerVertexIDs: cornerVertexIDs.build(),
                cornerEdgeIDs: cornerEdgeIDs.build()
            ),
            telemetry: telemetry
        )
    }
}
