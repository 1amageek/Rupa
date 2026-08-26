import Foundation
import RupaCADIntegration
import RupaCore
import RupaCoreTypes
import RupaEvaluation
@testable import RupaKit
import RupaProject
import RupaProjectModel
import SwiftCAD
import Synchronization
import Testing
@testable import RupaGeometry

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
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: DocumentTransactionRevision(0),
            expectedPublicationSequence: 0
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
func projectControllerReusesStagedCADEvaluationForProjectPublication() async throws {
    let probe = CADDocumentEvaluationProbe()
    let controller = try makeCADProjectController(
        document: .empty(named: "Reuse CAD"),
        evaluatorPreparer: ProbedCADProjectEvaluatorPreparer(probe: probe)
    )

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "integration.reuse-staged-cad",
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
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: DocumentTransactionRevision(0),
            expectedPublicationSequence: 0
        )
    )
    let state = try await controller.currentState()

    #expect(probe.evaluationCount == 0)
    #expect(state.documentGeneration == result.documentGeneration)
    #expect(state.transactionRevision == result.transactionRevision)
    #expect(state.publicationSequence == 1)
    #expect(state.cadInteraction?.generation == result.documentGeneration)
    #expect(state.evaluation.id.sourceRevision == result.transactionRevision)
    #expect(state.evaluation.occurrences.isEmpty == false)
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
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: DocumentTransactionRevision(0),
            expectedPublicationSequence: 1
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
func projectControllerUndoAndRedoRebuildCADEvaluationAtomically() async throws {
    let fixture = try extrudedCADDocument(named: "CAD History", depth: 1.0)
    let controller = try makeCADProjectController(document: fixture.document)
    let initial = try await controller.evaluateCurrent()
    let initialOccurrence = try #require(initial.occurrences.values.first {
        $0.reference.providerID == CADGeometrySourceProvider.identifier
    })

    let committed = try await controller.commit(
        ProjectSourceTransaction(
            name: "integration.cad-history",
            commands: [
                .setExtrudeDistance(
                    featureID: fixture.bodyFeatureID,
                    distance: .length(2.0, .meter)
                ),
            ],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: DocumentTransactionRevision(0),
            expectedPublicationSequence: 1
        )
    )
    let committedOccurrence = try #require(committed.evaluation.occurrences.values.first {
        $0.reference == initialOccurrence.reference
    })

    let undone = try await controller.undo(
        expectedTransactionRevision: DocumentTransactionRevision(1)
    )
    let undoneOccurrence = try #require(undone.evaluation.occurrences.values.first {
        $0.reference == initialOccurrence.reference
    })

    let redone = try await controller.redo(
        expectedTransactionRevision: DocumentTransactionRevision(2)
    )
    let redoneOccurrence = try #require(redone.evaluation.occurrences.values.first {
        $0.reference == initialOccurrence.reference
    })

    let initialDepth = initialOccurrence.worldBounds.maximum.z
        - initialOccurrence.worldBounds.minimum.z
    let committedDepth = committedOccurrence.worldBounds.maximum.z
        - committedOccurrence.worldBounds.minimum.z
    let undoneDepth = undoneOccurrence.worldBounds.maximum.z
        - undoneOccurrence.worldBounds.minimum.z
    let redoneDepth = redoneOccurrence.worldBounds.maximum.z
        - redoneOccurrence.worldBounds.minimum.z

    #expect(abs(undoneDepth - initialDepth) < 0.000_001)
    #expect(abs(redoneDepth - committedDepth) < 0.000_001)
    #expect(undone.transactionRevision == DocumentTransactionRevision(2))
    #expect(redone.transactionRevision == DocumentTransactionRevision(3))
    #expect(undone.publicationSequence == 3)
    #expect(redone.publicationSequence == 4)
    #expect(undone.cadInteraction?.generation == undone.documentGeneration)
    #expect(redone.cadInteraction?.generation == redone.documentGeneration)
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

@Test(.timeLimit(.minutes(1)))
func projectControllerMakesCADRepresentationEditableThroughModelingEvaluation() async throws {
    let fixture = try extrudedCADDocument(named: "Make Editable", depth: 1.0)
    let sceneNodeID = try bodySceneNodeID(
        in: fixture.document,
        featureID: fixture.bodyFeatureID
    )
    let controller = try makeCADProjectController(document: fixture.document)
    let sourceID: GeometrySourceID = "mesh.make-editable"
    let representationID: GeometryRepresentationID = "representation.make-editable"
    let prepared = try await controller.prepareMakeCADRepresentationEditableCommand(
        sceneNodeID: sceneNodeID,
        authoredMeshSourceID: sourceID,
        authoredMeshRepresentationID: representationID,
        expectedTransactionRevision: DocumentTransactionRevision(0)
    )
    guard case .makeCADRepresentationEditable(let command) = prepared else {
        Issue.record("Expected a Make Editable geometry source command.")
        return
    }

    #expect(command.evaluationSnapshotID.purpose == .modeling)
    #expect(command.evaluationSnapshotID.sourceRevision == DocumentTransactionRevision(0))
    #expect(command.evaluationCopyTelemetry.didCopy)
    #expect(command.evaluationCopyTelemetry.copiedBytes > 0)

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "integration.make-editable",
            geometrySourceCommands: [prepared],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: DocumentTransactionRevision(0),
            expectedPublicationSequence: 0
        )
    )
    let asset = try #require(result.document.authoredMeshAssets[sourceID])
    let object = try #require(
        result.document.productMetadata.sceneNodes[sceneNodeID]?.object
    )
    let selection = try #require(object.geometryRepresentations.selection)
    let occurrence = try #require(result.evaluation.occurrences.values.first {
        $0.representationID == representationID
    })
    guard case .makeEditable(let commandResult)? = result.geometrySourceCommandResults.first else {
        Issue.record("Expected a Make Editable command result.")
        return
    }

    #expect(selection.modeling == command.sourceRepresentationID)
    #expect(selection.presentation == representationID)
    #expect(object.geometryRepresentations.representations.count == 2)
    #expect(result.document.productMetadata.sceneNodes[sceneNodeID]?.reference == .body(fixture.bodyFeatureID))
    #expect(result.document.hasAuthoritativeCADSource)
    #expect(result.package.cadSource != nil)
    #expect(
        asset.provenance == .derivedFromCAD(
            representationID: command.sourceRepresentationID,
            sourceIdentity: command.sourceIdentity
        )
    )
    #expect(commandResult.cadSourceIdentity == command.sourceIdentity)
    #expect(commandResult.authoredMeshContentIdentity == asset.contentIdentity)
    #expect(commandResult.copyTelemetry == command.evaluationCopyTelemetry)
    #expect(!result.evaluation.copyTelemetry.didCopy)
    #expect(occurrence.reference == .authoredMesh(sourceID))
    #expect(occurrence.mesh.identity == sourceID)
    expectEveryMeshBufferShared(command.evaluatedMesh, asset.source)
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsForgedMakeEditableMeshPayloadWithoutPublication() async throws {
    let fixture = try extrudedCADDocument(named: "Forged Make Editable", depth: 1.0)
    let sceneNodeID = try bodySceneNodeID(
        in: fixture.document,
        featureID: fixture.bodyFeatureID
    )
    let controller = try makeCADProjectController(document: fixture.document)
    let prepared = try await controller.prepareMakeCADRepresentationEditableCommand(
        sceneNodeID: sceneNodeID,
        authoredMeshSourceID: "mesh.forged",
        authoredMeshRepresentationID: "representation.forged",
        expectedTransactionRevision: DocumentTransactionRevision(0)
    )
    guard case .makeCADRepresentationEditable(let command) = prepared else {
        Issue.record("Expected a Make Editable geometry source command.")
        return
    }
    let vertexID = try #require(command.evaluatedMesh.vertexIDs.first)
    let originalPosition = try command.evaluatedMesh.position(of: vertexID)
    var editor = MeshEditBuffer(source: command.evaluatedMesh)
    try editor.setVertexPosition(
        GeometryPoint3D(
            x: originalPosition.x + 10,
            y: originalPosition.y,
            z: originalPosition.z
        ),
        for: vertexID
    )
    let forgedMesh = try editor.commit().source
    let forgedCommand = try MakeCADRepresentationEditableCommand(
        sceneNodeID: command.sceneNodeID,
        sourceRepresentationID: command.sourceRepresentationID,
        sourceReference: command.sourceReference,
        evaluationSnapshotID: command.evaluationSnapshotID,
        sourceIdentity: command.sourceIdentity,
        evaluatedMesh: forgedMesh,
        evaluationCopyTelemetry: command.evaluationCopyTelemetry,
        authoredMeshSourceID: command.authoredMeshSourceID,
        authoredMeshRepresentationID: command.authoredMeshRepresentationID,
        switchesPresentationSelection: command.switchesPresentationSelection
    )
    let retainedPackage = await controller.currentPackage()
    var error: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "integration.reject-forged-make-editable",
                geometrySourceCommands: [.makeCADRepresentationEditable(forgedCommand)],
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: DocumentTransactionRevision(0),
                expectedPublicationSequence: 0
            )
        )
    } catch let caught as ProjectControllerError {
        error = caught
    }

    #expect(error?.code == .sourceMismatch)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    #expect(await controller.currentDocument().authoredMeshAssets.isEmpty)
    let currentPackage = await controller.currentPackage()
    #expect(currentPackage.documentID == retainedPackage.documentID)
    #expect(currentPackage.productSource == retainedPackage.productSource)
    #expect(currentPackage.cadSource == retainedPackage.cadSource)
    #expect(currentPackage.authoredMeshAssets == retainedPackage.authoredMeshAssets)
    #expect(currentPackage.persistedContentIdentity == retainedPackage.persistedContentIdentity)
}

@Test(.timeLimit(.minutes(1)))
func makeEditableValidationRejectsLatePublicationAfterConcurrentCommit() async throws {
    let fixture = try extrudedCADDocument(named: "Concurrent Make Editable", depth: 1.0)
    let sceneNodeID = try bodySceneNodeID(
        in: fixture.document,
        featureID: fixture.bodyFeatureID
    )
    let gate = NthEvaluationGate(blockedEvaluationNumber: 2)
    defer { gate.releaseBlockedEvaluation() }
    let controller = try makeCADProjectController(
        document: fixture.document,
        evaluatorPreparer: GatedCADProjectEvaluatorPreparer(gate: gate)
    )
    let prepared = try await controller.prepareMakeCADRepresentationEditableCommand(
        sceneNodeID: sceneNodeID,
        authoredMeshSourceID: "mesh.concurrent",
        authoredMeshRepresentationID: "representation.concurrent",
        expectedTransactionRevision: DocumentTransactionRevision(0)
    )
    let makeEditableCommit = Task {
        try await controller.commit(
            ProjectSourceTransaction(
                name: "integration.make-editable.concurrent",
                geometrySourceCommands: [prepared],
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: DocumentTransactionRevision(0),
                expectedPublicationSequence: 0
            )
        )
    }
    while !gate.didBlockEvaluation {
        try await Task.sleep(for: .milliseconds(1))
    }

    let winningCommit = try await controller.commit(
        ProjectSourceTransaction(
            name: "integration.concurrent-winner",
            commands: [.renameDocument(name: "Concurrent Winner")],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: DocumentTransactionRevision(0),
            expectedPublicationSequence: 0
        )
    )
    gate.releaseBlockedEvaluation()

    var makeEditableError: ProjectControllerError?
    do {
        _ = try await makeEditableCommit.value
    } catch let error as ProjectControllerError {
        makeEditableError = error
    }

    #expect(makeEditableError?.code == .revisionConflict)
    #expect(winningCommit.transactionRevision == DocumentTransactionRevision(1))
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Concurrent Winner")
    #expect(await controller.currentDocument().authoredMeshAssets.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func madeEditableMeshSurvivesSaveLoadAndRemainsIndependentFromLaterCADEdits() async throws {
    try await withCADProjectTemporaryDirectory { directory in
        let fixture = try extrudedCADDocument(named: "Independent Mesh", depth: 1.0)
        let sceneNodeID = try bodySceneNodeID(
            in: fixture.document,
            featureID: fixture.bodyFeatureID
        )
        let controller = try makeCADProjectController(document: fixture.document)
        let sourceID: GeometrySourceID = "mesh.independent"
        let representationID: GeometryRepresentationID = "representation.independent"
        let prepared = try await controller.prepareMakeCADRepresentationEditableCommand(
            sceneNodeID: sceneNodeID,
            authoredMeshSourceID: sourceID,
            authoredMeshRepresentationID: representationID,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let madeEditable = try await controller.commit(
            ProjectSourceTransaction(
                name: "integration.make-editable.save",
                geometrySourceCommands: [prepared],
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: DocumentTransactionRevision(0),
                expectedPublicationSequence: 0
            )
        )
        let retainedAsset = try #require(madeEditable.document.authoredMeshAssets[sourceID])
        let savedCADFingerprint = try madeEditable.document.cadDocument.sourceFingerprint(
            tolerance: .standard
        )
        let packageURL = directory.appendingPathComponent("editable.rupa")
        _ = try await controller.save(
            to: packageURL,
            expectedTransactionRevision: DocumentTransactionRevision(1)
        )

        let cadEdited = try await controller.commit(
            ProjectSourceTransaction(
                name: "integration.edit-cad-after-make-editable",
                commands: [
                    .setExtrudeDistance(
                        featureID: fixture.bodyFeatureID,
                        distance: .length(3, .meter)
                    ),
                ],
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: DocumentTransactionRevision(1),
                expectedPublicationSequence: 2
            )
        )
        let editedObject = try #require(
            cadEdited.document.productMetadata.sceneNodes[sceneNodeID]?.object
        )

        #expect(cadEdited.document.authoredMeshAssets[sourceID] == retainedAsset)
        #expect(editedObject.geometryRepresentations.selection?.modeling != representationID)
        #expect(editedObject.geometryRepresentations.selection?.presentation == representationID)
        #expect(
            try cadEdited.document.cadDocument.sourceFingerprint(tolerance: .standard)
                != savedCADFingerprint
        )
        #expect(!cadEdited.evaluation.copyTelemetry.didCopy)

        let loader = try makeCADProjectController(
            document: .empty(named: "Load Target")
        )
        let loaded = try await loader.load(
            from: packageURL,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let loadedObject = try #require(
            loaded.document.productMetadata.sceneNodes[sceneNodeID]?.object
        )

        #expect(loaded.document.authoredMeshAssets[sourceID] == retainedAsset)
        #expect(loadedObject.geometryRepresentations.selection?.presentation == representationID)
        #expect(
            try loaded.document.cadDocument.sourceFingerprint(tolerance: .standard)
                == savedCADFingerprint
        )
        #expect(loaded.evaluation.id.purpose == .presentation)
        #expect(!loaded.evaluation.copyTelemetry.didCopy)
    }
}

@Test(.timeLimit(.minutes(1)))
func makeEditableRejectsStaleRevisionAndRollsBackMixedCADMutation() async throws {
    let fixture = try extrudedCADDocument(named: "Make Editable Rollback", depth: 1.0)
    let sceneNodeID = try bodySceneNodeID(
        in: fixture.document,
        featureID: fixture.bodyFeatureID
    )
    let controller = try makeCADProjectController(document: fixture.document)
    let prepared = try await controller.prepareMakeCADRepresentationEditableCommand(
        sceneNodeID: sceneNodeID,
        authoredMeshSourceID: "mesh.rollback",
        authoredMeshRepresentationID: "representation.rollback",
        expectedTransactionRevision: DocumentTransactionRevision(0)
    )
    let originalFingerprint = try fixture.document.cadDocument.sourceFingerprint(
        tolerance: .standard
    )
    var mixedError: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "integration.make-editable.rollback",
                commands: [
                    .setExtrudeDistance(
                        featureID: fixture.bodyFeatureID,
                        distance: .length(2, .meter)
                    ),
                ],
                geometrySourceCommands: [prepared],
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: DocumentTransactionRevision(0),
                expectedPublicationSequence: 0
            )
        )
    } catch let error as ProjectControllerError {
        mixedError = error
    }

    let afterMixedFailure = await controller.currentDocument()
    let revisionAfterMixedFailure = await controller.currentTransactionRevision()
    #expect(mixedError?.code == .transactionInvalid)
    #expect(revisionAfterMixedFailure == DocumentTransactionRevision(0))
    #expect(afterMixedFailure.authoredMeshAssets.isEmpty)
    #expect(
        try afterMixedFailure.cadDocument.sourceFingerprint(tolerance: .standard)
            == originalFingerprint
    )

    _ = try await controller.commit(
        ProjectSourceTransaction(
            name: "integration.advance-revision",
            commands: [
                .setExtrudeDistance(
                    featureID: fixture.bodyFeatureID,
                    distance: .length(2, .meter)
                ),
            ],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: DocumentTransactionRevision(0),
            expectedPublicationSequence: 0
        )
    )
    let beforeStaleAttempt = await controller.currentDocument()
    var staleError: ProjectControllerError?
    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "integration.make-editable.stale",
                geometrySourceCommands: [prepared],
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: DocumentTransactionRevision(1),
                expectedPublicationSequence: 1
            )
        )
    } catch let error as ProjectControllerError {
        staleError = error
    }
    let afterStaleAttempt = await controller.currentDocument()
    let revisionAfterStaleAttempt = await controller.currentTransactionRevision()

    #expect(staleError?.code == .revisionConflict)
    #expect(revisionAfterStaleAttempt == DocumentTransactionRevision(1))
    #expect(afterStaleAttempt.authoredMeshAssets.isEmpty)
    #expect(
        try afterStaleAttempt.cadDocument.sourceFingerprint(tolerance: .standard)
            == beforeStaleAttempt.cadDocument.sourceFingerprint(tolerance: .standard)
    )
}

private func makeCADProjectController(
    document: DesignDocument,
    evaluatorPreparer: any ProjectEvaluatorPreparing =
        DefaultDesignDocumentProjectEvaluatorFactory()
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: evaluatorPreparer,
        projector: DesignDocumentProjectBridge()
    )
}

private final class CADDocumentEvaluationProbe: Sendable {
    private let count = Mutex(0)

    var evaluationCount: Int {
        count.withLock { $0 }
    }

    func recordEvaluation() {
        count.withLock { $0 += 1 }
    }
}

private struct ProbedCADDocumentEvaluator: CADDocumentEvaluating {
    let configuration: CADGeometryEvaluationConfiguration
    let probe: CADDocumentEvaluationProbe

    func evaluate(
        _ document: ValidatedCADDocument,
        reusing previous: EvaluatedDocument?
    ) throws -> EvaluatedDocument {
        probe.recordEvaluation()
        return try DefaultCADDocumentEvaluator(configuration: configuration).evaluate(
            document,
            reusing: previous
        )
    }
}

private struct ProbedCADProjectEvaluatorPreparer: ProjectEvaluatorPreparing {
    let probe: CADDocumentEvaluationProbe
    private let cache = CADDocumentEvaluationCache()

    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        let configuration = CADGeometryEvaluationConfiguration(
            tolerance: document.modelingSettings.tolerance,
            tessellationOptions: document.modelingSettings.tessellationOptions
        )
        let registry = try GeometrySourceEvaluationProviderRegistry(
            providers: [
                MeshSourceEvaluationProvider(),
                CADGeometrySourceProvider(
                    document: document.cadDocument,
                    evaluator: ProbedCADDocumentEvaluator(
                        configuration: configuration,
                        probe: probe
                    ),
                    cache: cache
                ),
            ]
        )
        return DesignDocumentProjectEvaluator(
            evaluator: ProjectEvaluationEngine(registry: registry),
            cadEvaluationCache: cache,
            cadConfiguration: configuration,
            reusableEvaluation: currentEvaluation
        )
    }
}

private final class NthEvaluationGate: Sendable {
    private struct State {
        var evaluationCount = 0
        var didBlockEvaluation = false
        var canFinishBlockedEvaluation = false
    }

    private let blockedEvaluationNumber: Int
    private let state = Mutex(State())

    init(blockedEvaluationNumber: Int) {
        self.blockedEvaluationNumber = blockedEvaluationNumber
    }

    var didBlockEvaluation: Bool {
        state.withLock { $0.didBlockEvaluation }
    }

    func waitIfNeeded() {
        let shouldBlock = state.withLock { state -> Bool in
            state.evaluationCount += 1
            guard state.evaluationCount == blockedEvaluationNumber else {
                return false
            }
            state.didBlockEvaluation = true
            return true
        }
        guard shouldBlock else {
            return
        }
        while !state.withLock({ $0.canFinishBlockedEvaluation }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func releaseBlockedEvaluation() {
        state.withLock { $0.canFinishBlockedEvaluation = true }
    }
}

private struct GatedCADProjectEvaluatorPreparer: ProjectEvaluatorPreparing {
    let gate: NthEvaluationGate
    private let base = DefaultDesignDocumentProjectEvaluatorFactory()

    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        GatedProjectEvaluator(
            base: try base.makeEvaluator(
                for: document,
                reusing: currentEvaluation
            ),
            gate: gate
        )
    }
}

private struct GatedProjectEvaluator: ProjectEvaluating {
    let base: any ProjectEvaluating
    let gate: NthEvaluationGate

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        gate.waitIfNeeded()
        return try base.evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
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

private func bodySceneNodeID(
    in document: DesignDocument,
    featureID: FeatureID
) throws -> SceneNodeID {
    try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(featureID)
    }?.key)
}

private func expectEveryMeshBufferShared(
    _ original: MeshSource,
    _ reidentified: MeshSource
) {
    #expect(original.vertexIDs.storage.chunkIdentities == reidentified.vertexIDs.storage.chunkIdentities)
    #expect(original.vertexPositions.storage.chunkIdentities == reidentified.vertexPositions.storage.chunkIdentities)
    #expect(original.edgeIDs.storage.chunkIdentities == reidentified.edgeIDs.storage.chunkIdentities)
    #expect(original.edgeEndpoints.storage.chunkIdentities == reidentified.edgeEndpoints.storage.chunkIdentities)
    #expect(original.faceIDs.storage.chunkIdentities == reidentified.faceIDs.storage.chunkIdentities)
    #expect(original.faceCornerRanges.storage.chunkIdentities == reidentified.faceCornerRanges.storage.chunkIdentities)
    #expect(original.cornerIDs.storage.chunkIdentities == reidentified.cornerIDs.storage.chunkIdentities)
    #expect(original.cornerVertexIDs.storage.chunkIdentities == reidentified.cornerVertexIDs.storage.chunkIdentities)
    #expect(original.cornerEdgeIDs.storage.chunkIdentities == reidentified.cornerEdgeIDs.storage.chunkIdentities)

    let originalLayers = original.attributes.sortedLayers()
    let reidentifiedLayers = reidentified.attributes.sortedLayers()
    #expect(originalLayers.map(\.descriptor.id) == reidentifiedLayers.map(\.descriptor.id))
    for (originalLayer, reidentifiedLayer) in zip(originalLayers, reidentifiedLayers) {
        expectAttributeStorageShared(originalLayer.values, reidentifiedLayer.values)
        #expect(
            originalLayer.indices?.storage.chunkIdentities
                == reidentifiedLayer.indices?.storage.chunkIdentities
        )
    }
}

private func expectAttributeStorageShared(
    _ original: GeometryAttributeStorage,
    _ reidentified: GeometryAttributeStorage
) {
    switch (original, reidentified) {
    case (.boolean(let lhs), .boolean(let rhs)):
        #expect(lhs.storage.chunkIdentities == rhs.storage.chunkIdentities)
    case (.int32(let lhs), .int32(let rhs)):
        #expect(lhs.storage.chunkIdentities == rhs.storage.chunkIdentities)
    case (.float32(let lhs), .float32(let rhs)):
        #expect(lhs.storage.chunkIdentities == rhs.storage.chunkIdentities)
    case (.float64(let lhs), .float64(let rhs)):
        #expect(lhs.storage.chunkIdentities == rhs.storage.chunkIdentities)
    case (.vector2(let lhs), .vector2(let rhs)):
        #expect(lhs.storage.chunkIdentities == rhs.storage.chunkIdentities)
    case (.vector3(let lhs), .vector3(let rhs)):
        #expect(lhs.storage.chunkIdentities == rhs.storage.chunkIdentities)
    case (.vector4(let lhs), .vector4(let rhs)):
        #expect(lhs.storage.chunkIdentities == rhs.storage.chunkIdentities)
    default:
        Issue.record("Expected matching geometry attribute storage types.")
    }
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
