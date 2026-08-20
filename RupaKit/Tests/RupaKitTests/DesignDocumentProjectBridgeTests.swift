import RupaKit
import RupaCoreTypes
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func designDocumentBridgeProjectsSceneHierarchyAndCADReferences() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let bridge = DesignDocumentProjectBridge()
    let project = try bridge.sourceModel(for: session.document)

    #expect(project.id.rawValue == "cad.\(session.document.id.description)")
    #expect(project.name == session.document.cadDocument.metadata.name)
    #expect(project.rootOccurrenceIDs.count == session.document.productMetadata.rootSceneNodeIDs.count)
    #expect(project.objectDefinitions.count == session.document.productMetadata.sceneNodes.count)
    #expect(project.occurrences.count == session.document.productMetadata.sceneNodes.count)

    let externalDefinitions = project.objectDefinitions.values.compactMap { definition -> GeometrySourceReference? in
        definition.geometry
    }
    #expect(externalDefinitions.contains { reference in
        guard case .external(let providerID, let sourceID, let outputID) = reference else {
            return false
        }
        return providerID == CADGeometrySourceProvider.identifier
            && sourceID == session.document.id.description
            && outputID != nil
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
        project,
        sourceRevision: DocumentTransactionRevision(session.generation.value)
    )

    #expect(snapshot.occurrences.values.contains { occurrence in
        occurrence.reference.providerID == CADGeometrySourceProvider.identifier
            && occurrence.mesh.faceIDs.count > 0
    })
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
