import RupaCoreTypes

/// Persists the next source-local element IDs so deleted IDs are never reused.
public struct MeshElementIDAllocationState: Codable, Equatable, Sendable {
    public private(set) var nextVertexID: MeshVertexID?
    public private(set) var nextEdgeID: MeshEdgeID?
    public private(set) var nextFaceID: MeshFaceID?
    public private(set) var nextCornerID: MeshCornerID?

    public init(
        nextVertexID: MeshVertexID? = MeshVertexID(0),
        nextEdgeID: MeshEdgeID? = MeshEdgeID(0),
        nextFaceID: MeshFaceID? = MeshFaceID(0),
        nextCornerID: MeshCornerID? = MeshCornerID(0)
    ) {
        self.nextVertexID = nextVertexID
        self.nextEdgeID = nextEdgeID
        self.nextFaceID = nextFaceID
        self.nextCornerID = nextCornerID
    }

    mutating func allocateVertexID() throws -> MeshVertexID {
        let id = try required(nextVertexID, domain: "vertex")
        nextVertexID = advanced(id).map(MeshVertexID.init)
        return id
    }

    mutating func allocateEdgeID() throws -> MeshEdgeID {
        let id = try required(nextEdgeID, domain: "edge")
        nextEdgeID = advanced(id).map(MeshEdgeID.init)
        return id
    }

    mutating func allocateFaceID() throws -> MeshFaceID {
        let id = try required(nextFaceID, domain: "face")
        nextFaceID = advanced(id).map(MeshFaceID.init)
        return id
    }

    mutating func allocateCornerID() throws -> MeshCornerID {
        let id = try required(nextCornerID, domain: "corner")
        nextCornerID = advanced(id).map(MeshCornerID.init)
        return id
    }

    func validateVertexAllocation(count: Int) throws {
        try validateAllocation(nextVertexID, count: count, domain: "vertex")
    }

    func validateEdgeAllocation(count: Int) throws {
        try validateAllocation(nextEdgeID, count: count, domain: "edge")
    }

    func validateFaceAllocation(count: Int) throws {
        try validateAllocation(nextFaceID, count: count, domain: "face")
    }

    func validateCornerAllocation(count: Int) throws {
        try validateAllocation(nextCornerID, count: count, domain: "corner")
    }

    func validate(
        vertexIDs: GeometryBuffer<MeshVertexID>,
        edgeIDs: GeometryBuffer<MeshEdgeID>,
        faceIDs: GeometryBuffer<MeshFaceID>,
        cornerIDs: GeometryBuffer<MeshCornerID>
    ) throws {
        try validate(nextVertexID, after: vertexIDs, domain: "vertex")
        try validate(nextEdgeID, after: edgeIDs, domain: "edge")
        try validate(nextFaceID, after: faceIDs, domain: "face")
        try validate(nextCornerID, after: cornerIDs, domain: "corner")
    }

    private func required<ID>(_ id: ID?, domain: String) throws -> ID {
        guard let id else {
            throw MeshSourceError(
                code: .idSpaceExhausted,
                message: "Mesh \(domain) ID space is exhausted."
            )
        }
        return id
    }

    private func advanced<ID>(_ id: ID) -> UInt64? where ID: MeshRawIdentifier {
        guard id.rawValue < UInt64.max else {
            return nil
        }
        return id.rawValue + 1
    }

    private func validateAllocation<ID>(
        _ nextID: ID?,
        count: Int,
        domain: String
    ) throws where ID: MeshRawIdentifier {
        guard count >= 0 else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh ID allocation counts cannot be negative."
            )
        }
        guard count > 0 else {
            return
        }
        guard let nextID,
              let finalOffset = UInt64(exactly: count - 1),
              nextID.rawValue <= UInt64.max - finalOffset else {
            throw MeshSourceError(
                code: .idSpaceExhausted,
                message: "Mesh \(domain) ID space is exhausted."
            )
        }
    }

    private func validate<ID>(
        _ nextID: ID?,
        after activeIDs: GeometryBuffer<ID>,
        domain: String
    ) throws where ID: MeshRawIdentifier {
        guard let nextID else {
            return
        }
        guard activeIDs.allSatisfy({ $0.rawValue < nextID.rawValue }) else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh next \(domain) ID must be greater than every active \(domain) ID."
            )
        }
    }
}

private protocol MeshRawIdentifier {
    var rawValue: UInt64 { get }
}

extension MeshVertexID: MeshRawIdentifier {}
extension MeshEdgeID: MeshRawIdentifier {}
extension MeshFaceID: MeshRawIdentifier {}
extension MeshCornerID: MeshRawIdentifier {}
