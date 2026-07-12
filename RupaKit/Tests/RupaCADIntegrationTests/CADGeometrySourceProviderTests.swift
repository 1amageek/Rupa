import Foundation
import RupaCore
import RupaCADIntegration
import RupaEvaluation
import RupaProjectModel
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsNonCADReferencesBeforeEvaluation() throws {
    let provider = CADGeometrySourceProvider(
        document: CADDocument(units: .meters)
    )
    var error: CADIntegrationError?

    do {
        _ = try provider.evaluate(
            reference: .mesh("mesh.source"),
            in: try ProjectSourceModel(id: "project", name: "Project")
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .unsupportedReference)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderRejectsReferencesForAnotherDocument() throws {
    let document = CADDocument(units: .meters)
    let provider = CADGeometrySourceProvider(document: document)
    var error: CADIntegrationError?

    do {
        _ = try provider.evaluate(
            reference: .external(
                providerID: "cad",
                sourceID: "another-document",
                outputID: UUID().uuidString
            ),
            in: try ProjectSourceModel(id: "project", name: "Project")
        )
    } catch let caught as CADIntegrationError {
        error = caught
    }

    #expect(error?.code == .documentMismatch)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderConvertsEvaluatedBodyMeshIntoUniversalGeometrySource() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluatedDocument = try DocumentEvaluator().evaluate(session.document.cadDocument)
    let bodyID = try #require(evaluatedDocument.meshes.keys.first)
    let provider = CADGeometrySourceProvider(document: session.document.cadDocument)
    let project = try ProjectSourceModel(id: "project.cad", name: "CAD")

    let result = try provider.evaluate(
        reference: .external(
            providerID: "cad",
            sourceID: session.document.cadDocument.id.description,
            outputID: bodyID.description
        ),
        in: project
    )

    #expect(result.mesh.vertexIDs.count > 0)
    #expect(result.mesh.faceIDs.count > 0)
    #expect(result.mesh.attributes.layer(for: "cad.normal") != nil)
    #expect(result.localBounds.maximum.x > result.localBounds.minimum.x)
}

@Test(.timeLimit(.minutes(1)))
func cadProviderParticipatesInProjectEvaluationThroughProviderBoundary() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let evaluatedDocument = try DocumentEvaluator().evaluate(session.document.cadDocument)
    let bodyID = try #require(evaluatedDocument.meshes.keys.first)
    let definition = ObjectDefinition(
        id: "cad.definition",
        name: "CAD Body",
        geometry: .external(
            providerID: "cad",
            sourceID: session.document.cadDocument.id.description,
            outputID: bodyID.description
        )
    )
    let occurrence = SceneOccurrence(id: "cad.occurrence", definitionID: definition.id)
    let project = try ProjectSourceModel(
        id: "project.cad-evaluation",
        name: "CAD Evaluation",
        objectDefinitions: [definition.id: definition],
        occurrences: [occurrence.id: occurrence],
        rootOccurrenceIDs: [occurrence.id]
    )
    let engine = ProjectEvaluationEngine(
        providers: [CADGeometrySourceProvider(document: session.document.cadDocument)]
    )

    let snapshot = try engine.evaluate(project)
    #expect(snapshot.occurrences[occurrence.id]?.mesh.faceIDs.count ?? 0 > 0)
}
