import Testing
@testable import RupaCore

@MainActor
@Test func bodyDisplaySnapshotServiceReportsEvaluatedBodyMeshAndTopology() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let snapshots = try BodyDisplaySnapshotService().snapshots(document: session.document)
    let snapshot = try #require(snapshots[bodyFeatureID])

    #expect(snapshot.featureID == bodyFeatureID)
    #expect(snapshot.mesh.positions.isEmpty == false)
    #expect(snapshot.mesh.indices.count >= 3)
    #expect(snapshot.bounds.maxX > snapshot.bounds.minX)
    #expect(snapshot.bounds.maxY > snapshot.bounds.minY)
    #expect(snapshot.bounds.maxZ > snapshot.bounds.minZ)
    #expect(snapshot.topology.faces.count == 6)
    #expect(snapshot.topology.edges.count == 12)
    #expect(snapshot.topology.vertices.count == 8)
    #expect(snapshot.topology.faces.allSatisfy { $0.componentID.generatedTopologyPersistentName != nil })
    #expect(snapshot.topology.edges.allSatisfy { $0.componentID.generatedTopologyPersistentName != nil })
    #expect(snapshot.topology.vertices.allSatisfy { $0.componentID.generatedTopologyPersistentName != nil })
}
