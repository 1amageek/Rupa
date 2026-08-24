import Foundation
import RupaCoreTypes
import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func meshSourceSupportsBoundaryLooseAndNonManifoldTopology() throws {
    var builder = MeshSourceBuilder(identity: "fixture.topology-coverage")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: -1, z: 0))
    let v4 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 1))
    _ = try builder.addVertex(GeometryPoint3D(x: 4, y: 4, z: 4))
    let looseEdgeID = try builder.addEdge(v2, v3)
    _ = try builder.addTriangle(v0, v1, v2)
    _ = try builder.addTriangle(v1, v0, v3)
    _ = try builder.addTriangle(v0, v1, v4)
    let source = try builder.build()

    let sharedEdgeKey = MeshUndirectedEdgeKey(first: v0, second: v1)
    let sharedEdgeID = try #require(
        source.edgeIDs.indices.first { index in
            let endpoints = source.edgeEndpoints[index]
            return MeshUndirectedEdgeKey(
                first: endpoints.start,
                second: endpoints.end
            ) == sharedEdgeKey
        }.map { source.edgeIDs[$0] }
    )

    #expect(source.vertexIDs.count == 6)
    #expect(source.faceIDs.count == 3)
    #expect(source.edgeIDs.contains(looseEdgeID))
    #expect(source.cornerEdgeIDs.filter { $0 == sharedEdgeID }.count == 3)
}

@Test(.timeLimit(.minutes(1)))
func meshSourceSupportsDisconnectedPolygonIslands() throws {
    var builder = MeshSourceBuilder(identity: "fixture.disconnected")
    let a0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let a1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let a2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let b0 = try builder.addVertex(GeometryPoint3D(x: 10, y: 0, z: 0))
    let b1 = try builder.addVertex(GeometryPoint3D(x: 11, y: 0, z: 0))
    let b2 = try builder.addVertex(GeometryPoint3D(x: 10, y: 1, z: 0))
    let firstFaceID = try builder.addTriangle(a0, a1, a2)
    let secondFaceID = try builder.addTriangle(b0, b1, b2)
    let source = try builder.build()

    #expect(source.edgeIDs.count == 6)
    #expect(
        try source.faceLoop(for: firstFaceID).map { try source.vertexID(of: $0) }
            == [a0, a1, a2]
    )
    #expect(
        try source.faceLoop(for: secondFaceID).map { try source.vertexID(of: $0) }
            == [b0, b1, b2]
    )
}

@Test(.timeLimit(.minutes(1)))
func meshEditCompactionPreservesPersistentElementIdentity() throws {
    var builder = MeshSourceBuilder(identity: "fixture.persistent-ids")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let v4 = try builder.addVertex(GeometryPoint3D(x: -1, y: 0, z: 0))
    let deletedFaceID = try builder.addTriangle(v0, v1, v2)
    let survivingFaceID = try builder.addTriangle(v0, v2, v3)
    let source = try builder.build()
    let survivingCornerIDs = try cornerIDs(in: source, for: survivingFaceID)

    var deletion = MeshEditBuffer(source: source)
    try deletion.deleteFace(deletedFaceID)
    let compacted = try deletion.commit().source
    var addition = MeshEditBuffer(source: compacted)
    let addedFaceID = try addition.addFace(vertexIDs: [v1, v3, v4])
    let expanded = try addition.commit().source
    let expandedSurvivingCorners = try cornerIDs(in: expanded, for: survivingFaceID)
    let addedCornerIDs = try cornerIDs(in: expanded, for: addedFaceID)

    #expect(addedFaceID.rawValue == 2)
    #expect(expandedSurvivingCorners == survivingCornerIDs)
    #expect(addedCornerIDs.map(\.rawValue) == [6, 7, 8])
    #expect(expanded.allocationState.nextFaceID == MeshFaceID(3))
    #expect(expanded.allocationState.nextCornerID == MeshCornerID(9))
}

@Test(.timeLimit(.minutes(1)))
func meshEditCompactionSharesUnchangedStorageAndMeasuresOnlyRebuiltTopology() throws {
    var builder = MeshSourceBuilder(identity: "fixture.compaction-sharing")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let v3 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    let deletedFaceID = try builder.addTriangle(v0, v1, v2)
    _ = try builder.addTriangle(v0, v2, v3)
    let source = try builder.build()
    var edit = MeshEditBuffer(source: source)
    try edit.deleteFace(deletedFaceID)

    let committed = try edit.commit()
    let expectedCopiedBytes = UInt64(
        MemoryLayout<MeshFaceID>.stride
            + MemoryLayout<MeshIndexRange>.stride
            + 3 * MemoryLayout<MeshCornerID>.stride
            + 3 * MemoryLayout<MeshVertexID>.stride
            + 3 * MemoryLayout<MeshEdgeID>.stride
    )

    #expect(committed.source.vertexIDs.storage.chunkIdentities == source.vertexIDs.storage.chunkIdentities)
    #expect(
        committed.source.vertexPositions.storage.chunkIdentities
            == source.vertexPositions.storage.chunkIdentities
    )
    #expect(committed.source.edgeIDs.storage.chunkIdentities == source.edgeIDs.storage.chunkIdentities)
    #expect(
        committed.source.edgeEndpoints.storage.chunkIdentities
            == source.edgeEndpoints.storage.chunkIdentities
    )
    #expect(committed.telemetry.copiedBytes == expectedCopiedBytes)
    #expect(committed.telemetry.events.allSatisfy { $0.reason == .sourceEdit })
}

@Test(.timeLimit(.minutes(1)))
func meshSourceBuilderReportsOneFinalPayloadMaterialization() throws {
    var builder = MeshSourceBuilder(identity: "fixture.builder-telemetry")
    let v0 = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let v1 = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let v2 = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addTriangle(v0, v1, v2)
    var telemetry = GeometryCopyTelemetry()
    let source = try builder.build(telemetry: &telemetry)
    let expectedCopiedBytes = UInt64(
        source.vertexIDs.count * MemoryLayout<MeshVertexID>.stride
            + source.vertexPositions.count * MemoryLayout<GeometryPoint3D>.stride
            + source.edgeIDs.count * MemoryLayout<MeshEdgeID>.stride
            + source.edgeEndpoints.count * MemoryLayout<MeshEdgeEndpoints>.stride
            + source.faceIDs.count * MemoryLayout<MeshFaceID>.stride
            + source.faceCornerRanges.count * MemoryLayout<MeshIndexRange>.stride
            + source.cornerIDs.count * MemoryLayout<MeshCornerID>.stride
            + source.cornerVertexIDs.count * MemoryLayout<MeshVertexID>.stride
            + source.cornerEdgeIDs.count * MemoryLayout<MeshEdgeID>.stride
    )

    #expect(telemetry.copiedBytes == expectedCopiedBytes)
    #expect(telemetry.events.count == 9)
    #expect(telemetry.events.allSatisfy { $0.reason == .bufferMaterialization })
}

@Test(.timeLimit(.minutes(1)))
func meshSourceRejectsMalformedTopologyContracts() throws {
    let allocationState = triangleAllocationState()

    #expect(throws: MeshSourceError.self) {
        _ = try makeTriangleSource(
            allocationState: allocationState,
            faceCornerRanges: GeometryBuffer([MeshIndexRange(start: 1, count: 3)])
        )
    }
    #expect(throws: MeshSourceError.self) {
        _ = try makeTriangleSource(
            allocationState: allocationState,
            cornerEdgeIDs: GeometryBuffer([MeshEdgeID(1), MeshEdgeID(1), MeshEdgeID(2)])
        )
    }
    #expect(throws: MeshSourceError.self) {
        _ = try makeTriangleSource(
            allocationState: MeshElementIDAllocationState(
                nextVertexID: MeshVertexID(2),
                nextEdgeID: MeshEdgeID(3),
                nextFaceID: MeshFaceID(1),
                nextCornerID: MeshCornerID(3)
            )
        )
    }
    #expect(throws: MeshSourceError.self) {
        _ = try makeTriangleSource(
            allocationState: MeshElementIDAllocationState(
                nextVertexID: MeshVertexID(3),
                nextEdgeID: MeshEdgeID(4),
                nextFaceID: MeshFaceID(1),
                nextCornerID: MeshCornerID(3)
            ),
            edgeIDs: GeometryBuffer([MeshEdgeID(0), MeshEdgeID(1), MeshEdgeID(2), MeshEdgeID(3)]),
            edgeEndpoints: GeometryBuffer([
                MeshEdgeEndpoints(start: MeshVertexID(0), end: MeshVertexID(1)),
                MeshEdgeEndpoints(start: MeshVertexID(1), end: MeshVertexID(2)),
                MeshEdgeEndpoints(start: MeshVertexID(2), end: MeshVertexID(0)),
                MeshEdgeEndpoints(start: MeshVertexID(1), end: MeshVertexID(0)),
            ])
        )
    }
    #expect(throws: MeshSourceError.self) {
        try MeshIndexRange(start: Int.max, count: 1).validate(upperBound: Int.max)
    }
}

@Test(.timeLimit(.minutes(1)))
func meshElementAllocationPreflightRejectsPartialExhaustion() throws {
    var state = MeshElementIDAllocationState(
        nextCornerID: MeshCornerID(UInt64.max)
    )

    #expect(throws: MeshSourceError.self) {
        try state.validateCornerAllocation(count: 2)
    }
    #expect(state.nextCornerID == MeshCornerID(UInt64.max))
    #expect(try state.allocateCornerID() == MeshCornerID(UInt64.max))
    #expect(state.nextCornerID == nil)
    #expect(throws: MeshSourceError.self) {
        _ = try state.allocateCornerID()
    }
}

@Test(.timeLimit(.minutes(1)))
func meshEditReportsExhaustedPersistentFaceIDs() throws {
    let source = try makeTriangleSource(
        allocationState: MeshElementIDAllocationState(
            nextVertexID: MeshVertexID(3),
            nextEdgeID: MeshEdgeID(3),
            nextFaceID: nil,
            nextCornerID: MeshCornerID(3)
        )
    )
    var edit = MeshEditBuffer(source: source)
    var error: MeshSourceError?

    do {
        _ = try edit.addFace(vertexIDs: [MeshVertexID(0), MeshVertexID(2), MeshVertexID(1)])
    } catch let caught as MeshSourceError {
        error = caught
    }

    #expect(error?.code == .idSpaceExhausted)
    #expect(!edit.hasEdits)
}

private func triangleAllocationState() -> MeshElementIDAllocationState {
    MeshElementIDAllocationState(
        nextVertexID: MeshVertexID(3),
        nextEdgeID: MeshEdgeID(3),
        nextFaceID: MeshFaceID(1),
        nextCornerID: MeshCornerID(3)
    )
}

private func cornerIDs(
    in source: MeshSource,
    for faceID: MeshFaceID
) throws -> [MeshCornerID] {
    guard let faceIndex = source.faceIDs.firstIndex(of: faceID) else {
        throw MeshSourceError(
            code: .invalidReference,
            message: "The test face must be present in the mesh source."
        )
    }
    let range = source.faceCornerRanges[faceIndex]
    return (range.start..<range.end).map { source.cornerIDs[$0] }
}

private func makeTriangleSource(
    allocationState: MeshElementIDAllocationState,
    edgeIDs: GeometryBuffer<MeshEdgeID> = GeometryBuffer([
        MeshEdgeID(0), MeshEdgeID(1), MeshEdgeID(2),
    ]),
    edgeEndpoints: GeometryBuffer<MeshEdgeEndpoints> = GeometryBuffer([
        MeshEdgeEndpoints(start: MeshVertexID(0), end: MeshVertexID(1)),
        MeshEdgeEndpoints(start: MeshVertexID(1), end: MeshVertexID(2)),
        MeshEdgeEndpoints(start: MeshVertexID(2), end: MeshVertexID(0)),
    ]),
    faceCornerRanges: GeometryBuffer<MeshIndexRange> = GeometryBuffer([
        MeshIndexRange(start: 0, count: 3),
    ]),
    cornerEdgeIDs: GeometryBuffer<MeshEdgeID> = GeometryBuffer([
        MeshEdgeID(0), MeshEdgeID(1), MeshEdgeID(2),
    ])
) throws -> MeshSource {
    try MeshSource(
        identity: "fixture.raw-triangle",
        allocationState: allocationState,
        vertexIDs: GeometryBuffer([MeshVertexID(0), MeshVertexID(1), MeshVertexID(2)]),
        vertexPositions: GeometryBuffer([
            GeometryPoint3D(x: 0, y: 0, z: 0),
            GeometryPoint3D(x: 1, y: 0, z: 0),
            GeometryPoint3D(x: 0, y: 1, z: 0),
        ]),
        edgeIDs: edgeIDs,
        edgeEndpoints: edgeEndpoints,
        faceIDs: GeometryBuffer([MeshFaceID(0)]),
        faceCornerRanges: faceCornerRanges,
        cornerIDs: GeometryBuffer([MeshCornerID(0), MeshCornerID(1), MeshCornerID(2)]),
        cornerVertexIDs: GeometryBuffer([MeshVertexID(0), MeshVertexID(1), MeshVertexID(2)]),
        cornerEdgeIDs: cornerEdgeIDs
    )
}
