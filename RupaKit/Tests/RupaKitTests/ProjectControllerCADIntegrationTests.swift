import Foundation
import RupaCADIntegration
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaKit
import RupaProject
import RupaProjectModel
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func projectControllerEvaluatesCADCreatedAfterInitialization() async throws {
    let controller = try makeCADProjectController(
        document: .empty(named: "Created CAD")
    )

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "integration.create-cad",
            commands: [
                .createExtrudedRectangle(
                    name: "Body",
                    plane: .xy,
                    width: .length(1.0, .meter),
                    height: .length(1.0, .meter),
                    depth: .length(1.0, .meter),
                    direction: .normal
                ),
            ],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    let occurrence = try #require(result.evaluation.occurrences.values.first {
        $0.reference.providerID == CADGeometrySourceProvider.identifier
    })
    #expect(occurrence.mesh.faceIDs.isEmpty == false)
    #expect(result.package.cadSource != nil)
    #expect(result.transactionRevision == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerEvaluatesChangedCADContentWithStableRepresentationIDs() async throws {
    let fixture = try extrudedCADDocument(named: "Stable CAD", depth: 1.0)
    let controller = try makeCADProjectController(document: fixture.document)
    let before = try await controller.evaluateCurrent()
    let beforeOccurrence = try #require(before.occurrences.values.first {
        $0.reference.providerID == CADGeometrySourceProvider.identifier
    })

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "integration.edit-cad",
            commands: [
                .setExtrudeDistance(
                    featureID: fixture.bodyFeatureID,
                    distance: .length(2.0, .meter)
                ),
            ],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    let afterOccurrence = try #require(result.evaluation.occurrences.values.first {
        $0.reference == beforeOccurrence.reference
    })
    let beforeDepth = beforeOccurrence.worldBounds.maximum.z
        - beforeOccurrence.worldBounds.minimum.z
    let afterDepth = afterOccurrence.worldBounds.maximum.z
        - afterOccurrence.worldBounds.minimum.z

    #expect(afterOccurrence.representationID == beforeOccurrence.representationID)
    #expect(afterDepth > beforeDepth * 1.9)
    #expect(afterDepth < beforeDepth * 2.1)
    #expect(result.evaluation.id.sourceRevision == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLoadEvaluatesTheLoadedCADDocument() async throws {
    try await withCADProjectTemporaryDirectory { directory in
        let original = try extrudedCADDocument(named: "Loaded CAD", depth: 1.0)
        var replacementDocument = original.document
        try replacementDocument.setExtrudeDistance(
            featureID: original.bodyFeatureID,
            distance: .length(3.0, .meter)
        )
        let replacementController = try makeCADProjectController(
            document: replacementDocument
        )
        let packageURL = directory.appendingPathComponent("replacement.rupa")
        _ = try await replacementController.save(
            to: packageURL,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )

        let controller = try makeCADProjectController(document: original.document)
        let before = try await controller.evaluateCurrent()
        let beforeOccurrence = try #require(before.occurrences.values.first {
            $0.reference.providerID == CADGeometrySourceProvider.identifier
        })
        let loaded = try await controller.load(
            from: packageURL,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let loadedOccurrence = try #require(loaded.evaluation.occurrences.values.first {
            $0.reference == beforeOccurrence.reference
        })
        let beforeDepth = beforeOccurrence.worldBounds.maximum.z
            - beforeOccurrence.worldBounds.minimum.z
        let loadedDepth = loadedOccurrence.worldBounds.maximum.z
            - loadedOccurrence.worldBounds.minimum.z

        #expect(loadedDepth > beforeDepth * 2.9)
        #expect(loadedDepth < beforeDepth * 3.1)
        #expect(loaded.transactionRevision == DocumentTransactionRevision(1))
    }
}

private func makeCADProjectController(
    document: DesignDocument
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private func extrudedCADDocument(
    named name: String,
    depth: Double
) throws -> (document: DesignDocument, bodyFeatureID: FeatureID) {
    var document = DesignDocument.empty(named: name)
    let bodyFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        depth: .length(depth, .meter),
        direction: .normal
    )
    return (document, bodyFeatureID)
}

private func withCADProjectTemporaryDirectory<Result: Sendable>(
    _ body: (URL) async throws -> Result
) async throws -> Result {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-project-cad-integration-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    do {
        let result = try await body(directory)
        try FileManager.default.removeItem(at: directory)
        return result
    } catch {
        let primaryError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let cleanupError {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Test failed and temporary cleanup also failed: "
                    + "\(primaryError); \(cleanupError)."
            )
        }
        throw primaryError
    }
}
