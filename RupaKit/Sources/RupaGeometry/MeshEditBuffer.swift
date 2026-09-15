import Foundation
import RupaCoreTypes

/// A single-owner staging buffer for one complete Mesh edit plan.
public struct MeshEditBuffer: Sendable {
    /// A complete face topology snapshot that is valid in the current staging state.
    struct FaceState: Sendable, Equatable {
        let id: MeshFaceID
        let vertexIDs: [MeshVertexID]
        let edgeIDs: [MeshEdgeID]
        let cornerIDs: [MeshCornerID]
    }

    /// The result of allocating one staged face and all of its corner references.
    struct StagedFaceResult: Sendable {
        let face: FaceState
        let createdEdgeIDs: [MeshEdgeID]
    }

    /// The face and local corner index owning one persistent corner ID.
    private struct CornerLocation: Sendable {
        let faceID: MeshFaceID
        let index: Int
    }

    private let source: MeshSource
    private let vertexIndexByID: [MeshVertexID: Int]
    private let faceIndexByID: [MeshFaceID: Int]
    private let edgeIndexByID: [MeshEdgeID: Int]
    private var edgeIDByVertices: [MeshUndirectedEdgeKey: MeshEdgeID]
    private var cornerLocations: [MeshCornerID: CornerLocation]
    private var allocationState: MeshElementIDAllocationState
    private var activeFaceCornerCount: Int
    private var vertexOverrides: [MeshVertexID: GeometryPoint3D] = [:]
    private var stagedVertexIDs: [MeshVertexID] = []
    private var stagedVertexPositions: [MeshVertexID: GeometryPoint3D] = [:]
    private var edgeOverrides: [MeshEdgeID: MeshEdgeEndpoints] = [:]
    private var stagedEdgeIDs: [MeshEdgeID] = []
    private var stagedEdgeEndpoints: [MeshEdgeID: MeshEdgeEndpoints] = [:]
    private var faceLoopOverrides: [MeshFaceID: FaceState] = [:]
    private var stagedFaceIDs: [MeshFaceID] = []
    private var stagedFaces: [MeshFaceID: FaceState] = [:]
    private var deletedFaceIDs: Set<MeshFaceID> = []
    private var vertexProvenance: [MeshVertexID: MeshVertexID] = [:]

    public init(source: MeshSource) {
        self.source = source
        var vertexIndexByID: [MeshVertexID: Int] = [:]
        vertexIndexByID.reserveCapacity(source.vertexIDs.count)
        for index in source.vertexIDs.indices {
            vertexIndexByID[source.vertexIDs[index]] = index
        }
        self.vertexIndexByID = vertexIndexByID

        var edgeIndexByID: [MeshEdgeID: Int] = [:]
        edgeIndexByID.reserveCapacity(source.edgeIDs.count)
        var edgeIDByVertices: [MeshUndirectedEdgeKey: MeshEdgeID] = [:]
        edgeIDByVertices.reserveCapacity(source.edgeIDs.count)
        for index in source.edgeIDs.indices {
            let edgeID = source.edgeIDs[index]
            edgeIndexByID[edgeID] = index
            let endpoints = source.edgeEndpoints[index]
            edgeIDByVertices[MeshUndirectedEdgeKey(
                first: endpoints.start,
                second: endpoints.end
            )] = edgeID
        }
        self.edgeIndexByID = edgeIndexByID
        self.edgeIDByVertices = edgeIDByVertices

        var faceIndexByID: [MeshFaceID: Int] = [:]
        faceIndexByID.reserveCapacity(source.faceIDs.count)
        var cornerLocations: [MeshCornerID: CornerLocation] = [:]
        cornerLocations.reserveCapacity(source.cornerIDs.count)
        for index in source.faceIDs.indices {
            let faceID = source.faceIDs[index]
            faceIndexByID[faceID] = index
            let range = source.faceCornerRanges[index]
            for cornerIndex in 0..<range.count {
                cornerLocations[source.cornerIDs[range.start + cornerIndex]] = CornerLocation(
                    faceID: faceID,
                    index: cornerIndex
                )
            }
        }
        self.faceIndexByID = faceIndexByID
        self.cornerLocations = cornerLocations
        self.allocationState = source.allocationState
        self.activeFaceCornerCount = source.cornerIDs.count
    }

    public var identity: GeometrySourceID {
        source.identity
    }

    public var hasEdits: Bool {
        !vertexOverrides.isEmpty
            || !stagedVertexIDs.isEmpty
            || !edgeOverrides.isEmpty
            || !stagedEdgeIDs.isEmpty
            || !faceLoopOverrides.isEmpty
            || !stagedFaceIDs.isEmpty
            || !deletedFaceIDs.isEmpty
            || allocationState != source.allocationState
    }

    /// Validates every persistent ID domain before a topology mutation allocates any ID.
    func preflightAllocation(
        vertexCount: Int,
        edgeCount: Int,
        faceCount: Int,
        cornerCount: Int
    ) throws {
        try allocationState.validateVertexAllocation(count: vertexCount)
        try allocationState.validateEdgeAllocation(count: edgeCount)
        try allocationState.validateFaceAllocation(count: faceCount)
        try allocationState.validateCornerAllocation(count: cornerCount)
    }

    public func position(for vertexID: MeshVertexID) throws -> GeometryPoint3D {
        if let position = stagedVertexPositions[vertexID] {
            return position
        }
        guard let index = vertexIndexByID[vertexID] else {
            throw invalidReference("Mesh edit references an unknown vertex.")
        }
        return vertexOverrides[vertexID] ?? source.vertexPositions[index]
    }

    /// Orders a bounded selection without rescanning the source vertex buffer.
    func orderedActiveVertexIDs(containing selected: Set<MeshVertexID>) -> [MeshVertexID] {
        var sourceSelection: [(index: Int, id: MeshVertexID)] = []
        sourceSelection.reserveCapacity(selected.count)
        for vertexID in selected {
            if let index = vertexIndexByID[vertexID] {
                sourceSelection.append((index: index, id: vertexID))
            }
        }
        sourceSelection.sort { $0.index < $1.index }
        var result = sourceSelection.map(\.id)
        result.reserveCapacity(sourceSelection.count + stagedVertexIDs.count)
        for vertexID in stagedVertexIDs where selected.contains(vertexID) {
            result.append(vertexID)
        }
        return result
    }

    /// Returns all active face topology in source order followed by staged order.
    func activeFaceStates() throws -> [FaceState] {
        var result: [FaceState] = []
        result.reserveCapacity(source.faceIDs.count + stagedFaceIDs.count)
        for faceID in source.faceIDs where !deletedFaceIDs.contains(faceID) {
            result.append(try faceState(for: faceID))
        }
        for faceID in stagedFaceIDs where !deletedFaceIDs.contains(faceID) {
            result.append(try faceState(for: faceID))
        }
        return result
    }

    /// Counts records that activeFaceStates must inspect before that scan starts.
    func activeFaceAnalysisRecordCount() throws -> Int {
        let faceIDCount = source.faceIDs.count.addingReportingOverflow(stagedFaceIDs.count)
        guard !faceIDCount.overflow else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh face analysis record count overflowed."
            )
        }
        let cornerRecordCount = activeFaceCornerCount.multipliedReportingOverflow(by: 3)
        guard !cornerRecordCount.overflow else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh corner analysis record count overflowed."
            )
        }
        let total = faceIDCount.partialValue.addingReportingOverflow(cornerRecordCount.partialValue)
        guard !total.overflow else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh face analysis record count overflowed."
            )
        }
        return total.partialValue
    }

    func activeEdgeIDs() -> [MeshEdgeID] {
        source.edgeIDs.map { $0 } + stagedEdgeIDs
    }

    /// Returns the active edge for an undirected endpoint pair in constant time.
    func existingEdgeID(
        start: MeshVertexID,
        end: MeshVertexID
    ) -> MeshEdgeID? {
        edgeIDByVertices[MeshUndirectedEdgeKey(first: start, second: end)]
    }

    func contains(_ element: MeshSelectionElement) -> Bool {
        switch element {
        case .vertex(let id):
            return vertexIndexByID[id] != nil || stagedVertexPositions[id] != nil
        case .edge(let id):
            return edgeIndexByID[id] != nil || stagedEdgeEndpoints[id] != nil
        case .face(let id):
            return (faceIndexByID[id] != nil || stagedFaces[id] != nil)
                && !deletedFaceIDs.contains(id)
        case .corner(let id):
            guard let location = cornerLocations[id],
                  !deletedFaceIDs.contains(location.faceID) else {
                return false
            }
            let face = stagedFaces[location.faceID]
                ?? faceLoopOverrides[location.faceID]
            if let face {
                guard face.cornerIDs.indices.contains(location.index) else {
                    return false
                }
                return face.cornerIDs[location.index] == id
            }
            guard let faceIndex = faceIndexByID[location.faceID] else {
                return false
            }
            let range = source.faceCornerRanges[faceIndex]
            guard location.index >= 0, location.index < range.count else {
                return false
            }
            return source.cornerIDs[range.start + location.index] == id
        }
    }

    func edgeEndpoints(for edgeID: MeshEdgeID) throws -> MeshEdgeEndpoints {
        if let endpoints = stagedEdgeEndpoints[edgeID] {
            return endpoints
        }
        if let endpoints = edgeOverrides[edgeID] {
            return endpoints
        }
        guard let index = edgeIndexByID[edgeID] else {
            throw invalidReference("Mesh edit references an unknown edge.")
        }
        return source.edgeEndpoints[index]
    }

    func faceState(for faceID: MeshFaceID) throws -> FaceState {
        guard !deletedFaceIDs.contains(faceID) else {
            throw invalidReference("Mesh edit references a deleted face.")
        }
        if let face = stagedFaces[faceID] {
            return face
        }
        if let face = faceLoopOverrides[faceID] {
            return face
        }
        guard let index = faceIndexByID[faceID] else {
            throw invalidReference("Mesh edit references an unknown face.")
        }
        let range = source.faceCornerRanges[index]
        return FaceState(
            id: faceID,
            vertexIDs: (range.start..<range.end).map { source.cornerVertexIDs[$0] },
            edgeIDs: (range.start..<range.end).map { source.cornerEdgeIDs[$0] },
            cornerIDs: (range.start..<range.end).map { source.cornerIDs[$0] }
        )
    }

    func faceStateContaining(cornerID: MeshCornerID) throws -> FaceState {
        guard let location = cornerLocations[cornerID] else {
            throw invalidReference("Mesh edit references an unknown corner.")
        }
        let face = try faceState(for: location.faceID)
        guard face.cornerIDs.indices.contains(location.index),
              face.cornerIDs[location.index] == cornerID else {
            throw invalidReference("Mesh edit corner location is inconsistent with its face loop.")
        }
        return face
    }

    /// Resolves a corner to its vertex without materializing the entire face loop.
    func vertexID(for cornerID: MeshCornerID) throws -> MeshVertexID {
        guard let location = cornerLocations[cornerID],
              !deletedFaceIDs.contains(location.faceID) else {
            throw invalidReference("Mesh edit references an unknown corner.")
        }
        if let face = stagedFaces[location.faceID] ?? faceLoopOverrides[location.faceID] {
            guard face.vertexIDs.indices.contains(location.index),
                  face.cornerIDs[location.index] == cornerID else {
                throw invalidReference("Mesh edit corner location is inconsistent with its face loop.")
            }
            return face.vertexIDs[location.index]
        }
        guard let faceIndex = faceIndexByID[location.faceID] else {
            throw invalidReference("Mesh edit references an unknown face.")
        }
        let range = source.faceCornerRanges[faceIndex]
        guard location.index >= 0, location.index < range.count else {
            throw invalidReference("Mesh edit corner location is inconsistent with its face loop.")
        }
        let sourceIndex = range.start + location.index
        guard source.cornerIDs[sourceIndex] == cornerID else {
            throw invalidReference("Mesh edit corner location is inconsistent with its face loop.")
        }
        return source.cornerVertexIDs[sourceIndex]
    }

    public mutating func setVertexPosition(
        _ position: GeometryPoint3D,
        for vertexID: MeshVertexID
    ) throws {
        try position.validate()
        if stagedVertexPositions[vertexID] != nil {
            stagedVertexPositions[vertexID] = position
            return
        }
        guard let index = vertexIndexByID[vertexID] else {
            throw invalidReference("Mesh edit cannot move an unknown vertex.")
        }
        let original = source.vertexPositions[index]
        if position == original {
            vertexOverrides.removeValue(forKey: vertexID)
        } else {
            vertexOverrides[vertexID] = position
        }
    }

    /// Allocates a persistent vertex ID during staging.
    ///
    /// `derivedFrom` names the vertex this one duplicates so that attribute
    /// layers can carry that vertex's values onto the new vertex at commit.
    /// Pass `nil` only for a vertex that inherits from no existing vertex; a
    /// dense vertex-domain attribute then rejects the commit.
    public mutating func addVertex(
        _ position: GeometryPoint3D,
        derivedFrom originVertexID: MeshVertexID?
    ) throws -> MeshVertexID {
        try position.validate()
        if let originVertexID {
            guard vertexIndexByID[originVertexID] != nil
                || stagedVertexPositions[originVertexID] != nil else {
                throw invalidReference("Mesh edit cannot derive a vertex from an unknown vertex.")
            }
        }
        try allocationState.validateVertexAllocation(count: 1)
        let id = try allocationState.allocateVertexID()
        stagedVertexIDs.append(id)
        stagedVertexPositions[id] = position
        if let originVertexID {
            vertexProvenance[id] = originVertexID
        }
        return id
    }

    public mutating func addFace(vertexIDs: [MeshVertexID]) throws -> MeshFaceID {
        try stageFace(vertexIDs: vertexIDs).face.id
    }

    /// Allocates a face and all required edge/corner IDs before commit.
    mutating func stageFace(vertexIDs: [MeshVertexID]) throws -> StagedFaceResult {
        guard vertexIDs.count >= 3,
              Set(vertexIDs).count == vertexIDs.count,
              vertexIDs.allSatisfy(containsSourceVertex) else {
            throw invalidFaceLoop("Added mesh faces require three or more unique source vertices.")
        }
        let nextActiveFaceCornerCount = activeFaceCornerCount.addingReportingOverflow(vertexIDs.count)
        guard !nextActiveFaceCornerCount.overflow else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh active face corner count overflowed."
            )
        }

        var missingEdgeCount = 0
        for index in vertexIDs.indices {
            let nextIndex = index + 1 == vertexIDs.count ? 0 : index + 1
            if existingEdgeID(start: vertexIDs[index], end: vertexIDs[nextIndex]) == nil {
                missingEdgeCount += 1
            }
        }
        try allocationState.validateEdgeAllocation(count: missingEdgeCount)
        try allocationState.validateFaceAllocation(count: 1)
        try allocationState.validateCornerAllocation(count: vertexIDs.count)

        var edgeIDs: [MeshEdgeID] = []
        var createdEdgeIDs: [MeshEdgeID] = []
        edgeIDs.reserveCapacity(vertexIDs.count)
        for index in vertexIDs.indices {
            let nextIndex = index + 1 == vertexIDs.count ? 0 : index + 1
            let edge = try stageEdge(
                start: vertexIDs[index],
                end: vertexIDs[nextIndex],
                forceNew: false
            )
            edgeIDs.append(edge.id)
            if edge.created {
                createdEdgeIDs.append(edge.id)
            }
        }

        let faceID = try allocationState.allocateFaceID()
        var cornerIDs: [MeshCornerID] = []
        cornerIDs.reserveCapacity(vertexIDs.count)
        for _ in vertexIDs {
            cornerIDs.append(try allocationState.allocateCornerID())
        }
        let face = FaceState(
            id: faceID,
            vertexIDs: vertexIDs,
            edgeIDs: edgeIDs,
            cornerIDs: cornerIDs
        )
        stagedFaceIDs.append(faceID)
        stagedFaces[faceID] = face
        for cornerIndex in face.cornerIDs.indices {
            cornerLocations[face.cornerIDs[cornerIndex]] = CornerLocation(
                faceID: faceID,
                index: cornerIndex
            )
        }
        activeFaceCornerCount = nextActiveFaceCornerCount.partialValue
        return StagedFaceResult(face: face, createdEdgeIDs: createdEdgeIDs)
    }

    /// Allocates a face with an explicitly prepared edge loop.
    mutating func stageFace(
        vertexIDs: [MeshVertexID],
        edgeIDs: [MeshEdgeID]
    ) throws -> StagedFaceResult {
        guard vertexIDs.count >= 3,
              vertexIDs.count == edgeIDs.count,
              Set(vertexIDs).count == vertexIDs.count,
              Set(edgeIDs).count == edgeIDs.count,
              vertexIDs.allSatisfy(containsVertex) else {
            throw invalidFaceLoop("Staged face loops require unique active vertices and edges.")
        }
        let nextActiveFaceCornerCount = activeFaceCornerCount.addingReportingOverflow(vertexIDs.count)
        guard !nextActiveFaceCornerCount.overflow else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh active face corner count overflowed."
            )
        }
        try allocationState.validateFaceAllocation(count: 1)
        try allocationState.validateCornerAllocation(count: vertexIDs.count)
        for index in vertexIDs.indices {
            let nextIndex = index + 1 == vertexIDs.count ? 0 : index + 1
            let endpoints = try self.edgeEndpoints(for: edgeIDs[index])
            guard MeshUndirectedEdgeKey(first: endpoints.start, second: endpoints.end)
                    == MeshUndirectedEdgeKey(
                        first: vertexIDs[index],
                        second: vertexIDs[nextIndex]
                    ) else {
                throw invalidFaceLoop("Staged face edges must connect consecutive loop vertices.")
            }
        }
        let faceID = try allocationState.allocateFaceID()
        let cornerIDs = try vertexIDs.map { _ in
            try allocationState.allocateCornerID()
        }
        let face = FaceState(
            id: faceID,
            vertexIDs: vertexIDs,
            edgeIDs: edgeIDs,
            cornerIDs: cornerIDs
        )
        stagedFaceIDs.append(faceID)
        stagedFaces[faceID] = face
        for cornerIndex in face.cornerIDs.indices {
            cornerLocations[face.cornerIDs[cornerIndex]] = CornerLocation(
                faceID: faceID,
                index: cornerIndex
            )
        }
        activeFaceCornerCount = nextActiveFaceCornerCount.partialValue
        return StagedFaceResult(face: face, createdEdgeIDs: [])
    }

    mutating func stageEdge(
        start: MeshVertexID,
        end: MeshVertexID,
        forceNew: Bool
    ) throws -> (id: MeshEdgeID, created: Bool) {
        guard start != end, containsVertex(start), containsVertex(end) else {
            throw invalidFaceLoop("Mesh edges require two distinct active vertices.")
        }
        if !forceNew {
            if let edgeID = existingEdgeID(start: start, end: end) {
                return (edgeID, false)
            }
        } else if existingEdgeID(start: start, end: end) != nil {
            throw invalidFaceLoop("Mesh edges must use unique undirected endpoint pairs.")
        }
        try allocationState.validateEdgeAllocation(count: 1)
        let id = try allocationState.allocateEdgeID()
        stagedEdgeIDs.append(id)
        stagedEdgeEndpoints[id] = MeshEdgeEndpoints(start: start, end: end)
        edgeIDByVertices[MeshUndirectedEdgeKey(first: start, second: end)] = id
        return (id, true)
    }

    mutating func replaceFaceLoop(
        faceID: MeshFaceID,
        vertexIDs: [MeshVertexID],
        edgeIDs: [MeshEdgeID]
    ) throws {
        let current = try faceState(for: faceID)
        guard current.vertexIDs.count == vertexIDs.count,
              vertexIDs.count == edgeIDs.count,
              Set(vertexIDs).count == vertexIDs.count,
              Set(edgeIDs).count == edgeIDs.count,
              vertexIDs.allSatisfy(containsVertex) else {
            throw invalidFaceLoop("A retained face must keep a valid loop length and vertices.")
        }
        for index in vertexIDs.indices {
            let nextIndex = index + 1 == vertexIDs.count ? 0 : index + 1
            let endpoints = try self.edgeEndpoints(for: edgeIDs[index])
            guard MeshUndirectedEdgeKey(first: endpoints.start, second: endpoints.end)
                    == MeshUndirectedEdgeKey(
                        first: vertexIDs[index],
                        second: vertexIDs[nextIndex]
                    ) else {
                throw invalidFaceLoop("A retained face edge must connect consecutive loop vertices.")
            }
        }
        let updated = FaceState(
            id: faceID,
            vertexIDs: vertexIDs,
            edgeIDs: edgeIDs,
            cornerIDs: current.cornerIDs
        )
        if stagedFaces[faceID] != nil {
            stagedFaces[faceID] = updated
        } else {
            faceLoopOverrides[faceID] = updated
        }
    }

    mutating func replaceEdgeEndpoints(
        _ edgeID: MeshEdgeID,
        start: MeshVertexID,
        end: MeshVertexID
    ) throws {
        guard start != end, containsVertex(start), containsVertex(end) else {
            throw invalidFaceLoop("Rewired mesh edges require two distinct active vertices.")
        }
        guard edgeIndexByID[edgeID] != nil || stagedEdgeEndpoints[edgeID] != nil else {
            throw invalidReference("Mesh edit cannot rewire an unknown edge.")
        }
        let endpoints = MeshEdgeEndpoints(start: start, end: end)
        let oldKey: MeshUndirectedEdgeKey
        do {
            let current = try edgeEndpoints(for: edgeID)
            oldKey = MeshUndirectedEdgeKey(first: current.start, second: current.end)
        } catch let error as MeshSourceError {
            throw error
        }
        let newKey = MeshUndirectedEdgeKey(first: start, second: end)
        if let existingEdgeID = edgeIDByVertices[newKey], existingEdgeID != edgeID {
            throw invalidFaceLoop("Mesh edges must use unique undirected endpoint pairs.")
        }
        if edgeIDByVertices[oldKey] == edgeID {
            edgeIDByVertices.removeValue(forKey: oldKey)
        }
        edgeIDByVertices[newKey] = edgeID
        if stagedEdgeEndpoints[edgeID] != nil {
            stagedEdgeEndpoints[edgeID] = endpoints
        } else {
            edgeOverrides[edgeID] = endpoints
        }
    }

    public mutating func deleteFace(_ faceID: MeshFaceID) throws {
        guard faceIndexByID[faceID] != nil || stagedFaces[faceID] != nil else {
            throw invalidReference("Mesh edit cannot delete an unknown face.")
        }
        guard !deletedFaceIDs.contains(faceID) else {
            return
        }
        let face = try faceState(for: faceID)
        let nextActiveFaceCornerCount = activeFaceCornerCount.subtractingReportingOverflow(face.cornerIDs.count)
        guard !nextActiveFaceCornerCount.overflow else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh active face corner count underflowed."
            )
        }
        activeFaceCornerCount = nextActiveFaceCornerCount.partialValue
        deletedFaceIDs.insert(faceID)
    }

    public func commit() throws -> MeshEditCommitResult {
        guard hasEdits else {
            return MeshEditCommitResult(
                source: source,
                telemetry: GeometryCopyTelemetry()
            )
        }
        if !hasTopologyEdits {
            return try commitVertexEdits()
        }
        return try commitTopologyEdits()
    }

    private var hasTopologyEdits: Bool {
        !stagedVertexIDs.isEmpty
            || !edgeOverrides.isEmpty
            || !stagedEdgeIDs.isEmpty
            || !faceLoopOverrides.isEmpty
            || !stagedFaceIDs.isEmpty
            || !deletedFaceIDs.isEmpty
    }

    private func commitVertexEdits() throws -> MeshEditCommitResult {
        var positions = source.vertexPositions.makeBuilder()
        for (vertexID, position) in vertexOverrides {
            guard let index = vertexIndexByID[vertexID] else {
                throw invalidReference("Mesh edit cannot commit an unknown vertex.")
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
        var positions = source.vertexPositions.makeBuilder()
        for vertexID in stagedVertexIDs {
            try positions.append(try position(for: vertexID))
        }
        for (vertexID, position) in vertexOverrides {
            guard let index = vertexIndexByID[vertexID] else {
                throw invalidReference("Mesh edit cannot commit an unknown vertex.")
            }
            try positions.replaceSubrange(
                index..<(index + 1),
                with: CollectionOfOne(position)
            )
        }

        var vertexIDs = source.vertexIDs.makeBuilder()
        for vertexID in stagedVertexIDs {
            try vertexIDs.append(vertexID)
        }

        var edgeIDs = source.edgeIDs.makeBuilder()
        var edgeEndpoints = source.edgeEndpoints.makeBuilder()
        for edgeID in source.edgeIDs {
            if let endpoints = edgeOverrides[edgeID],
               let index = edgeIndexByID[edgeID] {
                try edgeEndpoints.replaceSubrange(
                    index..<(index + 1),
                    with: CollectionOfOne(endpoints)
                )
            }
        }
        for edgeID in stagedEdgeIDs {
            try edgeIDs.append(edgeID)
            try edgeEndpoints.append(try self.edgeEndpoints(for: edgeID))
        }

        let activeFaces = try activeFaceStates()
        let requiresRebuild = !deletedFaceIDs.isEmpty
        let faceBuffers: (
            GeometryBuffer<MeshFaceID>,
            GeometryBuffer<MeshIndexRange>,
            GeometryBuffer<MeshCornerID>,
            GeometryBuffer<MeshVertexID>,
            GeometryBuffer<MeshEdgeID>
        )
        var faceTelemetry = GeometryCopyTelemetry()

        if requiresRebuild || activeFaces.count != source.faceIDs.count + stagedFaceIDs.count {
            var rebuiltFaceIDs = GeometryBufferConstructionBuffer<MeshFaceID>()
            var rebuiltFaceCornerRanges = GeometryBufferConstructionBuffer<MeshIndexRange>()
            var rebuiltCornerIDs = GeometryBufferConstructionBuffer<MeshCornerID>()
            var rebuiltCornerVertexIDs = GeometryBufferConstructionBuffer<MeshVertexID>()
            var rebuiltCornerEdgeIDs = GeometryBufferConstructionBuffer<MeshEdgeID>()
            rebuiltFaceIDs.reserveCapacity(activeFaces.count)
            rebuiltFaceCornerRanges.reserveCapacity(activeFaces.count)
            rebuiltCornerIDs.reserveCapacity(activeFaces.reduce(0) { $0 + $1.cornerIDs.count })
            rebuiltCornerVertexIDs.reserveCapacity(activeFaces.reduce(0) { $0 + $1.vertexIDs.count })
            rebuiltCornerEdgeIDs.reserveCapacity(activeFaces.reduce(0) { $0 + $1.edgeIDs.count })
            var cornerStart = 0
            for face in activeFaces {
                try rebuiltFaceIDs.append(face.id)
                try rebuiltFaceCornerRanges.append(
                    MeshIndexRange(start: cornerStart, count: face.cornerIDs.count)
                )
                for cornerID in face.cornerIDs {
                    try rebuiltCornerIDs.append(cornerID)
                }
                for vertexID in face.vertexIDs {
                    try rebuiltCornerVertexIDs.append(vertexID)
                }
                for edgeID in face.edgeIDs {
                    try rebuiltCornerEdgeIDs.append(edgeID)
                }
                cornerStart += face.cornerIDs.count
            }
            try rebuiltFaceIDs.recordCopy(reason: .sourceEdit, in: &faceTelemetry)
            try rebuiltFaceCornerRanges.recordCopy(reason: .sourceEdit, in: &faceTelemetry)
            try rebuiltCornerIDs.recordCopy(reason: .sourceEdit, in: &faceTelemetry)
            try rebuiltCornerVertexIDs.recordCopy(reason: .sourceEdit, in: &faceTelemetry)
            try rebuiltCornerEdgeIDs.recordCopy(reason: .sourceEdit, in: &faceTelemetry)
            faceBuffers = (
                rebuiltFaceIDs.build(),
                rebuiltFaceCornerRanges.build(),
                rebuiltCornerIDs.build(),
                rebuiltCornerVertexIDs.build(),
                rebuiltCornerEdgeIDs.build()
            )
        } else {
            var faceIDs = source.faceIDs.makeBuilder()
            var faceCornerRanges = source.faceCornerRanges.makeBuilder()
            var cornerIDs = source.cornerIDs.makeBuilder()
            var cornerVertexIDs = source.cornerVertexIDs.makeBuilder()
            var cornerEdgeIDs = source.cornerEdgeIDs.makeBuilder()
            let sourceFaceCount = source.faceIDs.count
            for face in activeFaces.dropFirst(sourceFaceCount) {
                let start = cornerIDs.count
                try faceIDs.append(face.id)
                try faceCornerRanges.append(
                    MeshIndexRange(start: start, count: face.cornerIDs.count)
                )
                for cornerID in face.cornerIDs {
                    try cornerIDs.append(cornerID)
                }
                for vertexID in face.vertexIDs {
                    try cornerVertexIDs.append(vertexID)
                }
                for edgeID in face.edgeIDs {
                    try cornerEdgeIDs.append(edgeID)
                }
            }
            for face in activeFaces.prefix(sourceFaceCount) {
                guard let sourceIndex = faceIndexByID[face.id] else {
                    continue
                }
                let sourceRange = source.faceCornerRanges[sourceIndex]
                let sourceFace = try faceStateFromSource(faceID: face.id)
                guard face != sourceFace else {
                    continue
                }
                try faceIDs.replaceSubrange(
                    sourceIndex..<(sourceIndex + 1),
                    with: CollectionOfOne(face.id)
                )
                try faceCornerRanges.replaceSubrange(
                    sourceIndex..<(sourceIndex + 1),
                    with: CollectionOfOne(sourceRange)
                )
                try cornerIDs.replaceSubrange(
                    sourceRange.start..<sourceRange.end,
                    with: face.cornerIDs
                )
                try cornerVertexIDs.replaceSubrange(
                    sourceRange.start..<sourceRange.end,
                    with: face.vertexIDs
                )
                try cornerEdgeIDs.replaceSubrange(
                    sourceRange.start..<sourceRange.end,
                    with: face.edgeIDs
                )
            }
            try faceTelemetry.record(contentsOf: faceIDs.telemetry)
            try faceTelemetry.record(contentsOf: faceCornerRanges.telemetry)
            try faceTelemetry.record(contentsOf: cornerIDs.telemetry)
            try faceTelemetry.record(contentsOf: cornerVertexIDs.telemetry)
            try faceTelemetry.record(contentsOf: cornerEdgeIDs.telemetry)
            faceBuffers = (
                faceIDs.build(),
                faceCornerRanges.build(),
                cornerIDs.build(),
                cornerVertexIDs.build(),
                cornerEdgeIDs.build()
            )
        }

        var telemetry = GeometryCopyTelemetry()
        try telemetry.record(contentsOf: vertexIDs.telemetry)
        try telemetry.record(contentsOf: positions.telemetry)
        try telemetry.record(contentsOf: edgeIDs.telemetry)
        try telemetry.record(contentsOf: edgeEndpoints.telemetry)
        try telemetry.record(contentsOf: faceTelemetry)

        let committedVertexIDs = vertexIDs.build()
        let committedPositions = positions.build()
        let committedEdgeIDs = edgeIDs.build()
        let committedEdgeEndpoints = edgeEndpoints.build()
        let attributes = try remappedAttributes(
            vertexIDs: committedVertexIDs,
            edgeIDs: committedEdgeIDs,
            faceIDs: faceBuffers.0,
            cornerIDs: faceBuffers.2,
            telemetry: &telemetry
        )

        return MeshEditCommitResult(
            source: try MeshSource(
                identity: source.identity,
                allocationState: allocationState,
                vertexIDs: committedVertexIDs,
                vertexPositions: committedPositions,
                edgeIDs: committedEdgeIDs,
                edgeEndpoints: committedEdgeEndpoints,
                faceIDs: faceBuffers.0,
                faceCornerRanges: faceBuffers.1,
                cornerIDs: faceBuffers.2,
                cornerVertexIDs: faceBuffers.3,
                cornerEdgeIDs: faceBuffers.4,
                attributes: attributes
            ),
            telemetry: telemetry
        )
    }

    /// Carries every attribute layer onto the committed elements by identity.
    ///
    /// A committed element takes the value of the source element that owns its
    /// ID. A duplicated vertex takes the value of the vertex it was derived
    /// from. A dense layer whose domain gained an element that resolves to no
    /// source element is a typed failure; a sparse layer drops the entries of
    /// removed elements and leaves created elements uncovered.
    private func remappedAttributes(
        vertexIDs: GeometryBuffer<MeshVertexID>,
        edgeIDs: GeometryBuffer<MeshEdgeID>,
        faceIDs: GeometryBuffer<MeshFaceID>,
        cornerIDs: GeometryBuffer<MeshCornerID>,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryAttributeSet {
        guard source.attributes.count > 0 else {
            return GeometryAttributeSet()
        }
        var sourceIndicesByDomain: [GeometryAttributeDomain: [Int?]] = [:]
        var layers: [GeometryAttributeLayer] = []
        layers.reserveCapacity(source.attributes.count)
        for layer in source.attributes.sortedLayers() {
            let domain = layer.descriptor.domain
            let sourceIndices: [Int?]
            if let cached = sourceIndicesByDomain[domain] {
                sourceIndices = cached
            } else {
                sourceIndices = try attributeSourceIndices(
                    domain: domain,
                    vertexIDs: vertexIDs,
                    edgeIDs: edgeIDs,
                    faceIDs: faceIDs,
                    cornerIDs: cornerIDs
                )
                sourceIndicesByDomain[domain] = sourceIndices
            }
            layers.append(
                try remappedLayer(
                    layer,
                    sourceIndices: sourceIndices,
                    telemetry: &telemetry
                )
            )
        }
        return try GeometryAttributeSet(layers: layers)
    }

    /// Maps each committed element of one domain to its source element index.
    private func attributeSourceIndices(
        domain: GeometryAttributeDomain,
        vertexIDs: GeometryBuffer<MeshVertexID>,
        edgeIDs: GeometryBuffer<MeshEdgeID>,
        faceIDs: GeometryBuffer<MeshFaceID>,
        cornerIDs: GeometryBuffer<MeshCornerID>
    ) throws -> [Int?] {
        switch domain {
        case .vertex:
            var indices: [Int?] = []
            indices.reserveCapacity(vertexIDs.count)
            for vertexID in vertexIDs {
                indices.append(try sourceVertexIndex(for: vertexID))
            }
            return indices
        case .edge:
            var indices: [Int?] = []
            indices.reserveCapacity(edgeIDs.count)
            for edgeID in edgeIDs {
                indices.append(edgeIndexByID[edgeID])
            }
            return indices
        case .face:
            var indices: [Int?] = []
            indices.reserveCapacity(faceIDs.count)
            for faceID in faceIDs {
                indices.append(faceIndexByID[faceID])
            }
            return indices
        case .corner:
            var sourceIndexByID: [MeshCornerID: Int] = [:]
            sourceIndexByID.reserveCapacity(source.cornerIDs.count)
            for index in source.cornerIDs.indices {
                sourceIndexByID[source.cornerIDs[index]] = index
            }
            var indices: [Int?] = []
            indices.reserveCapacity(cornerIDs.count)
            for cornerID in cornerIDs {
                indices.append(sourceIndexByID[cornerID])
            }
            return indices
        case .point, .curve, .instance:
            // A Mesh source never holds these domains, so their element count
            // is zero before and after the edit.
            return []
        }
    }

    /// Resolves a committed vertex to the source vertex whose values it takes.
    private func sourceVertexIndex(for vertexID: MeshVertexID) throws -> Int? {
        if let index = vertexIndexByID[vertexID] {
            return index
        }
        var current = vertexID
        var steps = 0
        while let origin = vertexProvenance[current] {
            if let index = vertexIndexByID[origin] {
                return index
            }
            current = origin
            steps += 1
            guard steps <= vertexProvenance.count else {
                throw invalidReference("Mesh edit vertex provenance forms a cycle.")
            }
        }
        return nil
    }

    private func remappedLayer(
        _ layer: GeometryAttributeLayer,
        sourceIndices: [Int?],
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryAttributeLayer {
        if layer.descriptor.isSparse {
            return try remappedSparseLayer(
                layer,
                sourceIndices: sourceIndices,
                telemetry: &telemetry
            )
        }
        return try remappedDenseLayer(
            layer,
            sourceIndices: sourceIndices,
            telemetry: &telemetry
        )
    }

    private func remappedDenseLayer(
        _ layer: GeometryAttributeLayer,
        sourceIndices: [Int?],
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryAttributeLayer {
        let valueCount = layer.values.count
        var picks: [Int] = []
        picks.reserveCapacity(sourceIndices.count)
        var isIdentity = sourceIndices.count == valueCount
        for (index, sourceIndex) in sourceIndices.enumerated() {
            guard let sourceIndex else {
                let domain = layer.descriptor.domain.rawValue
                let name = layer.descriptor.name
                throw MeshSourceError(
                    code: .unsupportedOperation,
                    message: "Mesh edit created a \(domain) element that inherits no dense attribute \"\(name)\"."
                )
            }
            guard sourceIndex < valueCount else {
                throw MeshSourceError(
                    code: .invalidBuffer,
                    message: "Mesh attribute remapping referenced a value outside its layer."
                )
            }
            if sourceIndex != index {
                isIdentity = false
            }
            picks.append(sourceIndex)
        }
        guard !isIdentity else {
            return layer
        }
        var remapped = layer
        remapped.values = try Self.gatheredStorage(
            layer.values,
            picking: picks,
            telemetry: &telemetry
        )
        return remapped
    }

    private func remappedSparseLayer(
        _ layer: GeometryAttributeLayer,
        sourceIndices: [Int?],
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryAttributeLayer {
        guard let entryIndices = layer.indices else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Sparse attribute layer is missing its index buffer."
            )
        }
        // A source element always precedes the elements derived from it, so the
        // first committed index wins and an entry stays on its own element.
        var committedIndexBySourceIndex: [Int: Int] = [:]
        committedIndexBySourceIndex.reserveCapacity(sourceIndices.count)
        for (committedIndex, sourceIndex) in sourceIndices.enumerated() {
            guard let sourceIndex,
                  committedIndexBySourceIndex[sourceIndex] == nil else {
                continue
            }
            committedIndexBySourceIndex[sourceIndex] = committedIndex
        }
        var picks: [Int] = []
        var remappedIndices: [UInt32] = []
        picks.reserveCapacity(entryIndices.count)
        remappedIndices.reserveCapacity(entryIndices.count)
        var isIdentity = true
        for entry in entryIndices.indices {
            let sourceIndex = Int(entryIndices[entry])
            guard let committedIndex = committedIndexBySourceIndex[sourceIndex] else {
                isIdentity = false
                continue
            }
            if committedIndex != sourceIndex {
                isIdentity = false
            }
            picks.append(entry)
            remappedIndices.append(UInt32(committedIndex))
        }
        guard !isIdentity else {
            return layer
        }
        var remapped = layer
        remapped.values = try Self.gatheredStorage(
            layer.values,
            picking: picks,
            telemetry: &telemetry
        )
        var construction = GeometryBufferConstructionBuffer<UInt32>()
        construction.reserveCapacity(remappedIndices.count)
        for index in remappedIndices {
            try construction.append(index)
        }
        try construction.recordCopy(reason: .sourceEdit, in: &telemetry)
        remapped.indices = construction.build()
        return remapped
    }

    private static func gatheredStorage(
        _ storage: GeometryAttributeStorage,
        picking picks: [Int],
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryAttributeStorage {
        switch storage {
        case .boolean(let buffer):
            return .boolean(try gathered(buffer, picking: picks, telemetry: &telemetry))
        case .int32(let buffer):
            return .int32(try gathered(buffer, picking: picks, telemetry: &telemetry))
        case .float32(let buffer):
            return .float32(try gathered(buffer, picking: picks, telemetry: &telemetry))
        case .float64(let buffer):
            return .float64(try gathered(buffer, picking: picks, telemetry: &telemetry))
        case .vector2(let buffer):
            return .vector2(try gathered(buffer, picking: picks, telemetry: &telemetry))
        case .vector3(let buffer):
            return .vector3(try gathered(buffer, picking: picks, telemetry: &telemetry))
        case .vector4(let buffer):
            return .vector4(try gathered(buffer, picking: picks, telemetry: &telemetry))
        }
    }

    private static func gathered<Element: Codable & Sendable>(
        _ buffer: GeometryBuffer<Element>,
        picking picks: [Int],
        telemetry: inout GeometryCopyTelemetry
    ) throws -> GeometryBuffer<Element> {
        var construction = GeometryBufferConstructionBuffer<Element>()
        construction.reserveCapacity(picks.count)
        for index in picks {
            try construction.append(buffer[index])
        }
        try construction.recordCopy(reason: .sourceEdit, in: &telemetry)
        return construction.build()
    }

    private func faceStateFromSource(faceID: MeshFaceID) throws -> FaceState {
        guard let index = faceIndexByID[faceID] else {
            throw invalidReference("Mesh edit references an unknown source face.")
        }
        let range = source.faceCornerRanges[index]
        return FaceState(
            id: faceID,
            vertexIDs: (range.start..<range.end).map { source.cornerVertexIDs[$0] },
            edgeIDs: (range.start..<range.end).map { source.cornerEdgeIDs[$0] },
            cornerIDs: (range.start..<range.end).map { source.cornerIDs[$0] }
        )
    }

    private func containsVertex(_ vertexID: MeshVertexID) -> Bool {
        vertexIndexByID[vertexID] != nil || stagedVertexPositions[vertexID] != nil
    }

    private func containsSourceVertex(_ vertexID: MeshVertexID) -> Bool {
        vertexIndexByID[vertexID] != nil
    }

    private func invalidReference(_ message: String) -> MeshSourceError {
        MeshSourceError(code: .invalidReference, message: message)
    }

    private func invalidFaceLoop(_ message: String) -> MeshSourceError {
        MeshSourceError(code: .invalidFaceLoop, message: message)
    }
}
