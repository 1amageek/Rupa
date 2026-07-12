import RupaKit
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
        return providerID == "cad"
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
    let snapshot = try bridge.evaluationEngine(for: session.document).evaluate(project)

    #expect(snapshot.occurrences.values.contains { occurrence in
        occurrence.reference.providerID == "cad" && occurrence.mesh.faceIDs.count > 0
    })
}
