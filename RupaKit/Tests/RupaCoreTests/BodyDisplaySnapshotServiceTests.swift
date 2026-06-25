import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@Test func bodyDisplaySnapshotMeshSharesStorageAcrossValueCopiesAndPreservesCodableValueSemantics() throws {
    let mesh = BodyDisplaySnapshot.Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ],
        indices: [0, 1, 2]
    )
    let copiedMesh = mesh
    let decodedMesh = try JSONDecoder().decode(
        BodyDisplaySnapshot.Mesh.self,
        from: try JSONEncoder().encode(mesh)
    )

    #expect(copiedMesh == mesh)
    #expect(copiedMesh.sharesStorage(with: mesh))
    #expect(copiedMesh.storageIdentity == mesh.storageIdentity)
    #expect(decodedMesh == mesh)
    #expect(decodedMesh.sharesStorage(with: mesh) == false)
    #expect(decodedMesh.storageIdentity != mesh.storageIdentity)
}

@MainActor
@Test func bodyDisplaySnapshotServiceReportsEvaluatedBodyMeshAndTopology() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let service = BodyDisplaySnapshotService()
    let evaluatedDocument = try CADPipeline
        .modelingDefault(for: session.document)
        .evaluate(session.document.cadDocument)
    let documentSnapshots = try service.snapshots(document: session.document)
    let evaluatedDocumentSnapshots = service.snapshots(evaluatedDocument: evaluatedDocument)

    #expect(evaluatedDocumentSnapshots == documentSnapshots)

    let snapshots = evaluatedDocumentSnapshots
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

@MainActor
@Test func bodyDisplaySnapshotServiceReusesEvaluatedDocumentWithoutPipelineOverride() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluatedDocument = try CADPipeline
        .modelingDefault(for: session.document)
        .evaluate(session.document.cadDocument)
    let service = BodyDisplaySnapshotService(
        pipeline: CADPipeline(
            evaluator: DocumentEvaluator(featureEvaluator: FailingFeatureEvaluator())
        )
    )

    let firstSnapshots = service.snapshots(evaluatedDocument: evaluatedDocument)
    let secondSnapshots = service.snapshots(evaluatedDocument: evaluatedDocument)

    #expect(firstSnapshots.isEmpty == false)
    #expect(secondSnapshots == firstSnapshots)
    do {
        _ = try service.snapshots(document: session.document)
        Issue.record("Body display snapshots should report the injected evaluation failure.")
    } catch let error as EditorError {
        #expect(error.code == .evaluationFailed)
        #expect(error.message.contains("Injected evaluator should not be used."))
    }
}

private struct FailingFeatureEvaluator: FeatureEvaluating {
    func evaluate(feature _: FeatureNode, context _: EvaluationContext) throws -> EvaluationResult {
        throw FeatureEvaluationError.unsupportedOperation("Injected evaluator should not be used.")
    }
}
