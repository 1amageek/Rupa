import Foundation
import RupaCoreTypes

public struct MeshSource: Codable, Equatable, Sendable {
    public let identity: GeometrySourceID
    public let allocationState: MeshElementIDAllocationState
    public let vertexIDs: GeometryBuffer<MeshVertexID>
    public let vertexPositions: GeometryBuffer<GeometryPoint3D>
    public let edgeIDs: GeometryBuffer<MeshEdgeID>
    public let edgeEndpoints: GeometryBuffer<MeshEdgeEndpoints>
    public let faceIDs: GeometryBuffer<MeshFaceID>
    public let faceCornerRanges: GeometryBuffer<MeshIndexRange>
    public let cornerIDs: GeometryBuffer<MeshCornerID>
    public let cornerVertexIDs: GeometryBuffer<MeshVertexID>
    public let cornerEdgeIDs: GeometryBuffer<MeshEdgeID>
    public let attributes: GeometryAttributeSet

    public init(
        identity: GeometrySourceID = GeometrySourceID(),
        allocationState: MeshElementIDAllocationState,
        vertexIDs: GeometryBuffer<MeshVertexID>,
        vertexPositions: GeometryBuffer<GeometryPoint3D>,
        edgeIDs: GeometryBuffer<MeshEdgeID>,
        edgeEndpoints: GeometryBuffer<MeshEdgeEndpoints>,
        faceIDs: GeometryBuffer<MeshFaceID>,
        faceCornerRanges: GeometryBuffer<MeshIndexRange>,
        cornerIDs: GeometryBuffer<MeshCornerID>,
        cornerVertexIDs: GeometryBuffer<MeshVertexID>,
        cornerEdgeIDs: GeometryBuffer<MeshEdgeID>,
        attributes: GeometryAttributeSet = GeometryAttributeSet()
    ) throws {
        self.identity = identity
        self.allocationState = allocationState
        self.vertexIDs = vertexIDs
        self.vertexPositions = vertexPositions
        self.edgeIDs = edgeIDs
        self.edgeEndpoints = edgeEndpoints
        self.faceIDs = faceIDs
        self.faceCornerRanges = faceCornerRanges
        self.cornerIDs = cornerIDs
        self.cornerVertexIDs = cornerVertexIDs
        self.cornerEdgeIDs = cornerEdgeIDs
        self.attributes = attributes
        try validate()
    }

    public func validate() throws {
        do {
            try identity.validate()
        } catch let error as EditorError {
            throw MeshSourceError(code: .invalidIdentity, message: error.message)
        }
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

        let vertexSet = try validateUnique(vertexIDs, label: "vertex")
        let edgeSet = try validateUnique(edgeIDs, label: "edge")
        _ = try validateUnique(faceIDs, label: "face")
        _ = try validateUnique(cornerIDs, label: "corner")
        try allocationState.validate(
            vertexIDs: vertexIDs,
            edgeIDs: edgeIDs,
            faceIDs: faceIDs,
            cornerIDs: cornerIDs
        )
        for position in vertexPositions {
            try position.validate()
        }

        var endpointsByEdgeID: [MeshEdgeID: MeshEdgeEndpoints] = [:]
        var edgeIDsByEndpoints: [MeshUndirectedEdgeKey: MeshEdgeID] = [:]
        endpointsByEdgeID.reserveCapacity(edgeIDs.count)
        edgeIDsByEndpoints.reserveCapacity(edgeIDs.count)
        for endpoints in edgeEndpoints {
            guard endpoints.start != endpoints.end,
                  vertexSet.contains(endpoints.start),
                  vertexSet.contains(endpoints.end) else {
                throw invalid("Edges must reference two distinct existing vertices.")
            }
        }
        for (edgeID, endpoints) in zip(edgeIDs, edgeEndpoints) {
            let key = MeshUndirectedEdgeKey(
                first: endpoints.start,
                second: endpoints.end
            )
            guard edgeIDsByEndpoints.updateValue(edgeID, forKey: key) == nil else {
                throw MeshSourceError(
                    code: .duplicateID,
                    message: "Mesh edges must use unique undirected endpoint pairs."
                )
            }
            endpointsByEdgeID[edgeID] = endpoints
        }
        for edgeID in cornerEdgeIDs {
            guard edgeSet.contains(edgeID) else {
                throw invalid("Corners must reference existing edges.")
            }
        }
        for vertexID in cornerVertexIDs {
            guard vertexSet.contains(vertexID) else {
                throw invalid("Corners must reference existing vertices.")
            }
        }
        var expectedCornerStart = 0
        for faceRange in faceCornerRanges {
            try faceRange.validate(upperBound: cornerIDs.count)
            guard faceRange.count >= 3 else {
                throw invalid("Faces must contain at least three corners.")
            }
            guard faceRange.start == expectedCornerStart else {
                throw MeshSourceError(
                    code: .invalidFaceLoop,
                    message: "Mesh face ranges must partition the corner buffers in source order."
                )
            }
            var faceVertexIDs: Set<MeshVertexID> = []
            for cornerIndex in faceRange.start..<faceRange.end {
                let vertexID = cornerVertexIDs[cornerIndex]
                // A triangle's three checked edges cover every vertex pair;
                // distinct edge endpoints already reject any repeated vertex.
                guard faceRange.count == 3 || faceVertexIDs.insert(vertexID).inserted else {
                    throw MeshSourceError(
                        code: .invalidFaceLoop,
                        message: "Mesh faces must not repeat vertices in one loop."
                    )
                }
                let nextCornerIndex =
                    cornerIndex + 1 == faceRange.end
                    ? faceRange.start
                    : cornerIndex + 1
                let nextVertexID = cornerVertexIDs[nextCornerIndex]
                let edgeID = cornerEdgeIDs[cornerIndex]
                guard let endpoints = endpointsByEdgeID[edgeID],
                      MeshUndirectedEdgeKey(
                        first: endpoints.start,
                        second: endpoints.end
                      ) == MeshUndirectedEdgeKey(
                        first: vertexID,
                        second: nextVertexID
                      ) else {
                    throw MeshSourceError(
                        code: .invalidFaceLoop,
                        message: "Each mesh corner edge must connect its vertex to the next face vertex."
                    )
                }
            }
            expectedCornerStart = faceRange.end
        }
        guard expectedCornerStart == cornerIDs.count else {
            throw MeshSourceError(
                code: .invalidFaceLoop,
                message: "Mesh face ranges must cover every corner exactly once."
            )
        }
        try attributes.validate(
            counts: GeometryAttributeDomainCounts(
                vertex: vertexIDs.count,
                edge: edgeIDs.count,
                face: faceIDs.count,
                corner: cornerIDs.count
            )
        )
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

    public func vertexID(of cornerID: MeshCornerID) throws -> MeshVertexID {
        guard let index = cornerIDs.firstIndex(of: cornerID) else {
            throw MeshSourceError(
                code: .invalidReference,
                message: "Mesh corner \(cornerID.rawValue) is not present in the source."
            )
        }
        return cornerVertexIDs[index]
    }

    public func bounds() throws -> GeometryBounds3D {
        try GeometryBounds3D(points: vertexPositions)
    }

    /// Returns the same immutable geometry storage under a new source identity.
    ///
    /// Every geometry buffer and attribute layer remains shared. This operation
    /// changes source authority identity without materializing element payloads.
    public func reidentified(as identity: GeometrySourceID) throws -> MeshSource {
        try MeshSource(
            identity: identity,
            allocationState: allocationState,
            vertexIDs: vertexIDs,
            vertexPositions: vertexPositions,
            edgeIDs: edgeIDs,
            edgeEndpoints: edgeEndpoints,
            faceIDs: faceIDs,
            faceCornerRanges: faceCornerRanges,
            cornerIDs: cornerIDs,
            cornerVertexIDs: cornerVertexIDs,
            cornerEdgeIDs: cornerEdgeIDs,
            attributes: attributes
        )
    }

    private func validateUnique<Element: Hashable>(
        _ values: GeometryBuffer<Element>,
        label: String
    ) throws -> Set<Element> {
        let unique = Set(values)
        guard unique.count == values.count else {
            throw MeshSourceError(
                code: .duplicateID,
                message: "Mesh \(label) IDs must be unique."
            )
        }
        return unique
    }

    private func invalid(_ message: String) -> MeshSourceError {
        MeshSourceError(code: .invalidBuffer, message: message)
    }
}
