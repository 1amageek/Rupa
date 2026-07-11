import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Suite("Validated design document mutations")
struct ValidatedDesignDocumentMutationTests {
    @Test(.timeLimit(.minutes(1)))
    func extrudeDistanceEditProducesReusableValidation() throws {
        let session = EditorSession()
        let creation = try session.execute(.createExtrudedRectangle(
            name: "Box",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(5.0, .millimeter),
            direction: .normal
        ))
        let featureID = try #require(creation.primaryFeatureID)
        let sourceValidation = try #require(
            session.currentEvaluationCache?.validatedDocument
        )
        var document = session.document

        let updatedValidation = try document.setExtrudeDistance(
            featureID: featureID,
            distance: .length(12.0, .millimeter),
            validatedDocument: sourceValidation
        )

        #expect(updatedValidation.document.cadDocument.designGraph.revision.value
            == sourceValidation.document.cadDocument.designGraph.revision.value + 1)
        #expect(updatedValidation.document.cadDocument.designGraph.dependencies
            == sourceValidation.document.cadDocument.designGraph.dependencies)
        _ = try updatedValidation.document.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func documentStorePublishesUpdatedValidationWithIncrementalEvaluation() throws {
        let store = CADDocumentStore()
        let creation = try store.apply(.createExtrudedRectangle(
            name: "Box",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(5.0, .millimeter),
            direction: .normal
        ))
        let featureID = try #require(creation.primaryFeatureID)

        let edit = try store.apply(.setExtrudeDistance(
            featureID: featureID,
            distance: .length(12.0, .millimeter)
        ))

        #expect(edit.createdFeatureIDs.isEmpty)
        let cache = try #require(store.currentEvaluationCache)
        #expect(cache.validatedDocument.document.cadDocument.designGraph.revision
            == store.document.cadDocument.designGraph.revision)
        #expect(cache.evaluatedDocument.evaluationMetrics.rebuiltFeatureCount == 1)
        #expect(cache.evaluatedDocument.evaluationMetrics.reusedFeatureCount == 1)
        #expect(cache.evaluatedDocument.evaluationMetrics.tessellatedBodyCount == 1)
    }
}
