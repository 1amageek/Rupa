import Foundation
import RupaKit
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func designDocumentBridgeProjectsSceneHierarchyAndCADReferences() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let bridge = DesignDocumentProjectBridge()
    let project = try bridge.sourceModel(for: session.document)

    #expect(project.id.rawValue == "project.\(session.document.id.description)")
    #expect(project.name == session.document.cadDocument.metadata.name)
    #expect(project.rootOccurrenceIDs.count == session.document.productMetadata.rootSceneNodeIDs.count)
    #expect(project.objectDefinitions.count == session.document.productMetadata.sceneNodes.count)
    #expect(project.occurrences.count == session.document.productMetadata.sceneNodes.count)

    let cadDefinitions = project.objectDefinitions.values.compactMap { definition -> GeometrySourceReference? in
        definition.representations.source(for: .modeling)
    }
    #expect(cadDefinitions.contains { reference in
        guard case .cad(let sourceID, let outputID) = reference else {
            return false
        }
        return sourceID == session.document.id.description
            && UUID(uuidString: outputID) != nil
    })
}

@Test(.timeLimit(.minutes(1)))
func designDocumentBridgeFeedsCADEvaluationThroughUniversalProjectModel() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let bridge = DesignDocumentProjectBridge()
    let project = try bridge.sourceModel(for: session.document)
    let evaluator = try DefaultDesignDocumentProjectEvaluatorFactory()
        .makeEvaluator(
            for: session.document,
            reusing: session.currentEvaluation
        )
    let snapshot = try evaluator.evaluate(
        project: project,
        purpose: .presentation,
        revision: DocumentTransactionRevision(session.generation.value)
    )

    #expect(snapshot.occurrences.values.contains { occurrence in
        occurrence.reference.providerID == CADGeometrySourceProvider.identifier
            && occurrence.mesh.faceIDs.count > 0
    })
}

@Test(.timeLimit(.minutes(1)))
func designDocumentBridgeProjectsAllRepresentationsAndAuthoredMeshAssets() throws {
    let session = EditorSession()
    let commandResult = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(commandResult.primaryFeatureID)
    var document = session.document
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(object.geometryRepresentations.selection?.modeling)
    let mesh = try bridgeTriangleMesh()
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID = "representation.presentation-mesh"
    document.authoredMeshAssets[asset.id] = asset
    object.geometryRepresentations.representations[meshRepresentationID] = GeometryRepresentation(
        id: meshRepresentationID,
        source: .authoredMesh(asset.id)
    )
    object.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = object

    let project = try DesignDocumentProjectBridge().sourceModel(for: document)
    let definitionID = ObjectDefinitionID(rawValue: "object.\(bodyNodeID.description)")
    let definition = try #require(project.objectDefinitions[definitionID])
    let evaluator = try DefaultDesignDocumentProjectEvaluatorFactory()
        .makeEvaluator(for: document, reusing: nil)
    let modelingSnapshot = try evaluator.evaluate(
        project: project,
        purpose: .modeling,
        revision: DocumentTransactionRevision(1)
    )
    let presentationSnapshot = try evaluator.evaluate(
        project: project,
        purpose: .presentation,
        revision: DocumentTransactionRevision(1)
    )
    let modeled = try #require(modelingSnapshot.occurrences.values.first {
        $0.definitionID == definitionID
    })
    let presented = try #require(presentationSnapshot.occurrences.values.first {
        $0.definitionID == definitionID
    })

    #expect(project.authoredMeshAssets[asset.id]?.provenance == .created)
    #expect(definition.representations.representations.count == 2)
    #expect(definition.representations.selection?.modeling == cadRepresentationID)
    #expect(definition.representations.selection?.presentation == meshRepresentationID)
    #expect(modeled.representationID == cadRepresentationID)
    #expect(modeled.reference == object.geometryRepresentations.source(for: .modeling))
    #expect(modeled.mesh != mesh)
    #expect(modeled.mesh.faceIDs.count > 0)
    #expect(modelingSnapshot.copyTelemetry.didCopy)
    #expect(presented.representationID == meshRepresentationID)
    #expect(presented.reference == GeometrySourceReference.authoredMesh(asset.id))
    #expect(presented.mesh == mesh)
    #expect(presentationSnapshot.copyTelemetry.didCopy == false)
}

@Test(.timeLimit(.minutes(1)))
func designDocumentProjectSnapshotBuilderCarriesSourceRevisionIntoViewport() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let snapshot = try await DesignDocumentProjectSnapshotBuilder().build(
        document: session.document,
        generation: session.generation,
        currentEvaluation: session.currentEvaluation
    )

    #expect(snapshot.documentGeneration == session.generation)
    #expect(snapshot.sourceRevision == DocumentTransactionRevision(session.generation.value))
    #expect(snapshot.evaluation.id.sourceRevision == snapshot.sourceRevision)
    #expect(snapshot.evaluation.id.purpose == .presentation)
    #expect(snapshot.viewport.snapshotID == snapshot.evaluation.id)
}

@Test(.timeLimit(.minutes(1)))
func designDocumentProjectSnapshotBuilderRejectsAStaleReusableEvaluation() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let currentEvaluation = try #require(session.currentEvaluation)
    var error: DesignDocumentProjectBridgeError?

    do {
        _ = try await DesignDocumentProjectSnapshotBuilder().build(
            document: session.document,
            generation: try session.generation.advanced(),
            currentEvaluation: currentEvaluation
        )
    } catch let caught as DesignDocumentProjectBridgeError {
        error = caught
    }

    #expect(error?.code == .staleEvaluation)
}

private func bridgeTriangleMesh() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "mesh.bridge-presentation")
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}
