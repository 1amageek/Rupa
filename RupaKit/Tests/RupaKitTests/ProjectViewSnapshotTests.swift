import Foundation
import RupaCADIntegration
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProject
import RupaProjectModel
import SwiftCAD
import Testing
@testable import RupaGeometry
@testable import RupaKit

@Test(.timeLimit(.minutes(1)))
func projectWorkspacePublishesOneCoherentCADViewAndHistoryState() async throws {
    let controller = try projectViewController(
        document: .empty(named: "CAD View")
    )
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()

    let created = try await workspace.commit(
        ProjectSourceTransaction(
            name: "view.create-cad",
            commands: [
                .createExtrudedRectangle(
                    name: "Body",
                    plane: .xy,
                    width: .length(1, .meter),
                    height: .length(1, .meter),
                    depth: .length(1, .meter),
                    direction: .normal
                ),
            ],
            expectedTransactionRevision: initial.transactionRevision
        )
    )
    let document = await controller.currentDocument()
    let item = try #require(created.viewport.items.first)
    let sceneNodeID = try #require(created.sceneNodeID(for: item.id))
    let object = try #require(document.productMetadata.sceneNodes[sceneNodeID]?.object)

    #expect(created.publicationSequence > initial.publicationSequence)
    #expect(created.transactionRevision == DocumentTransactionRevision(1))
    #expect(created.viewport.snapshotID.sourceRevision == created.transactionRevision)
    #expect(created.viewport.snapshotID.purpose == .presentation)
    #expect(item.reference.providerID == CADGeometrySourceProvider.identifier)
    #expect(
        item.representationID
            == object.geometryRepresentations.selection?.presentation
    )
    #expect(
        created.cadInteraction?.matches(
            document: document,
            generation: created.documentGeneration
        ) == true
    )

    let undone = try await workspace.undo()
    #expect(undone.publicationSequence > created.publicationSequence)
    #expect(undone.transactionRevision == DocumentTransactionRevision(2))
    #expect(undone.viewport.items.isEmpty)
    #expect(undone.canRedo)

    let redone = try await workspace.redo()
    #expect(redone.publicationSequence > undone.publicationSequence)
    #expect(redone.transactionRevision == DocumentTransactionRevision(3))
    #expect(redone.viewport.items.count == 1)
    #expect(redone.canUndo)
}

@Test(.timeLimit(.minutes(1)))
func projectViewPreservesMeshOnlyStorageAndExplicitNavigation() async throws {
    let document = try projectViewMeshOnlyDocument(named: "Mesh View")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let controller = try projectViewController(document: document)
    let workspace = await ProjectWorkspace(project: controller)

    let view = try await workspace.evaluate()
    let item = try #require(view.viewport.items.first)
    let sceneNodeID = try #require(view.sceneNodeID(for: item.id))
    let node = try #require(document.productMetadata.sceneNodes[sceneNodeID])

    #expect(view.viewport.items.count == 1)
    #expect(view.cadInteraction == nil)
    #expect(item.reference == .authoredMesh(asset.id))
    expectProjectViewSharedStorage(item.mesh, asset.source)
    #expect(node.reference == .authoredMesh(asset.id))
}

@Test(.timeLimit(.minutes(1)))
func projectViewUsesTheMixedObjectsPresentationAuthorityWithoutMeshCopy() async throws {
    let document = try projectViewCADAndMeshDocument(named: "Mixed View")
    let asset = try #require(document.authoredMeshAssets.values.first)
    let body = try #require(document.productMetadata.sceneNodes.values.first {
        $0.object?.category == .body
    })
    let selection = try #require(body.object?.geometryRepresentations.selection)
    let controller = try projectViewController(document: document)
    let workspace = await ProjectWorkspace(project: controller)

    let view = try await workspace.evaluate()
    let item = try #require(view.viewport.items.first)

    #expect(document.hasAuthoritativeCADSource)
    #expect(selection.modeling != selection.presentation)
    #expect(item.representationID == selection.presentation)
    #expect(item.reference == .authoredMesh(asset.id))
    expectProjectViewSharedStorage(item.mesh, asset.source)
}

@Test(.timeLimit(.minutes(1)))
func projectViewBuilderRejectsAnEvaluationFromAnotherTransactionRevision() async throws {
    let controller = try projectViewController(
        document: try projectViewMeshOnlyDocument(named: "Revision View")
    )
    _ = try await controller.evaluateCurrent()
    let state = try await controller.currentState()
    let mismatched = ProjectStateSnapshot(
        document: state.document,
        package: state.package,
        documentGeneration: state.documentGeneration,
        transactionRevision: try state.transactionRevision.advanced(),
        publicationSequence: state.publicationSequence,
        isDirty: state.isDirty,
        canUndo: state.canUndo,
        canRedo: state.canRedo,
        selection: state.selection,
        workspaceState: state.workspaceState,
        evaluationSource: state.evaluationSource,
        cadInteraction: state.cadInteraction,
        evaluation: state.evaluation
    )
    var error: ProjectViewSnapshotError?

    do {
        _ = try ProjectViewSnapshotBuilder().build(from: mismatched)
    } catch let caught as ProjectViewSnapshotError {
        error = caught
    }

    #expect(error?.code == .revisionMismatch)
}

@Test(.timeLimit(.minutes(1)))
func projectViewBuilderRejectsCADInteractionFromAnotherDocumentGeneration() async throws {
    let controller = try projectViewController(
        document: .empty(named: "CAD Interaction View")
    )
    _ = try await controller.commit(
        ProjectSourceTransaction(
            name: "view.create-cad-interaction",
            commands: [
                .createExtrudedRectangle(
                    name: "Body",
                    plane: .xy,
                    width: .length(1, .meter),
                    height: .length(1, .meter),
                    depth: .length(1, .meter),
                    direction: .normal
                ),
            ],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    let state = try await controller.currentState()
    _ = try #require(state.cadInteraction)
    let mismatched = ProjectStateSnapshot(
        document: state.document,
        package: state.package,
        documentGeneration: try state.documentGeneration.advanced(),
        transactionRevision: state.transactionRevision,
        publicationSequence: state.publicationSequence,
        isDirty: state.isDirty,
        canUndo: state.canUndo,
        canRedo: state.canRedo,
        selection: state.selection,
        workspaceState: state.workspaceState,
        evaluationSource: state.evaluationSource,
        cadInteraction: state.cadInteraction,
        evaluation: state.evaluation
    )
    var error: ProjectViewSnapshotError?

    do {
        _ = try ProjectViewSnapshotBuilder().build(from: mismatched)
    } catch let caught as ProjectViewSnapshotError {
        error = caught
    }

    #expect(error?.code == .staleCADInteraction)
}

@Test(.timeLimit(.minutes(1)))
func projectViewBuilderRejectsMismatchedProjectAndPurpose() async throws {
    let controller = try projectViewController(
        document: try projectViewMeshOnlyDocument(named: "Authority View")
    )
    _ = try await controller.evaluateCurrent()
    let state = try await controller.currentState()
    var otherSource = state.evaluationSource
    otherSource.id = "project.other-view"
    let wrongSourceState = projectViewState(
        from: state,
        evaluationSource: otherSource
    )
    let modelingEvaluation = EvaluatedProjectSnapshot(
        id: EvaluationSnapshotID(
            projectID: state.evaluation.projectID,
            purpose: .modeling,
            sourceRevision: state.transactionRevision
        ),
        projectID: state.evaluation.projectID,
        occurrences: state.evaluation.occurrences,
        copyTelemetry: state.evaluation.copyTelemetry
    )
    let wrongPurposeState = projectViewState(
        from: state,
        evaluation: modelingEvaluation
    )
    var sourceError: ProjectViewSnapshotError?
    var purposeError: ProjectViewSnapshotError?

    do {
        _ = try ProjectViewSnapshotBuilder().build(from: wrongSourceState)
    } catch let caught as ProjectViewSnapshotError {
        sourceError = caught
    }
    do {
        _ = try ProjectViewSnapshotBuilder().build(from: wrongPurposeState)
    } catch let caught as ProjectViewSnapshotError {
        purposeError = caught
    }

    #expect(sourceError?.code == .sourceMismatch)
    #expect(purposeError?.code == .purposeMismatch)
}

@Test(.timeLimit(.minutes(1)))
func projectViewBuilderRejectsGeometryOutsidePresentationAuthority() async throws {
    let controller = try projectViewController(
        document: try projectViewMeshOnlyDocument(named: "Geometry Authority View")
    )
    _ = try await controller.evaluateCurrent()
    let state = try await controller.currentState()
    let occurrence = try #require(state.evaluation.occurrences.values.first)
    let mismatchedOccurrence = EvaluatedOccurrenceSnapshot(
        occurrenceID: occurrence.occurrenceID,
        definitionID: occurrence.definitionID,
        representationID: "representation.unselected",
        reference: occurrence.reference,
        mesh: occurrence.mesh,
        copyTelemetry: occurrence.copyTelemetry,
        worldTransform: occurrence.worldTransform,
        worldBounds: occurrence.worldBounds
    )
    let evaluation = EvaluatedProjectSnapshot(
        id: state.evaluation.id,
        projectID: state.evaluation.projectID,
        occurrences: [occurrence.occurrenceID: mismatchedOccurrence],
        copyTelemetry: state.evaluation.copyTelemetry
    )
    var error: ProjectViewSnapshotError?

    do {
        _ = try ProjectViewSnapshotBuilder().build(
            from: projectViewState(from: state, evaluation: evaluation)
        )
    } catch let caught as ProjectViewSnapshotError {
        error = caught
    }

    #expect(error?.code == .sourceMismatch)
}

@Test(.timeLimit(.minutes(1)))
func projectViewBuilderRejectsAnOccurrenceWithoutExplicitNavigation() async throws {
    let controller = try projectViewController(
        document: try projectViewMeshOnlyDocument(named: "Navigation View")
    )
    _ = try await controller.evaluateCurrent()
    let state = try await controller.currentState()
    let occurrence = try #require(state.evaluation.occurrences.values.first)
    var source = state.evaluationSource
    var sourceOccurrence = try #require(
        source.occurrences[occurrence.occurrenceID]
    )
    source.occurrences.removeValue(forKey: occurrence.occurrenceID)
    let unmappedID: SceneOccurrenceID = "scene.unmapped-view"
    sourceOccurrence.id = unmappedID
    source.occurrences[unmappedID] = sourceOccurrence
    let unmappedOccurrence = EvaluatedOccurrenceSnapshot(
        occurrenceID: unmappedID,
        definitionID: occurrence.definitionID,
        representationID: occurrence.representationID,
        reference: occurrence.reference,
        mesh: occurrence.mesh,
        copyTelemetry: occurrence.copyTelemetry,
        worldTransform: occurrence.worldTransform,
        worldBounds: occurrence.worldBounds
    )
    let evaluation = EvaluatedProjectSnapshot(
        id: state.evaluation.id,
        projectID: state.evaluation.projectID,
        occurrences: [unmappedID: unmappedOccurrence],
        copyTelemetry: state.evaluation.copyTelemetry
    )
    var error: ProjectViewSnapshotError?

    do {
        _ = try ProjectViewSnapshotBuilder().build(
            from: projectViewState(
                from: state,
                evaluationSource: source,
                evaluation: evaluation
            )
        )
    } catch let caught as ProjectViewSnapshotError {
        error = caught
    }

    #expect(error?.code == .missingNavigation)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRequiresAnInitialViewBeforeHistoryMutation() async throws {
    let controller = try projectViewController(
        document: .empty(named: "Unavailable View")
    )
    let workspace = await ProjectWorkspace(project: controller)
    var error: ProjectViewSnapshotError?

    do {
        _ = try await workspace.undo()
    } catch let caught as ProjectViewSnapshotError {
        error = caught
    }
    let revision = await controller.currentTransactionRevision()

    #expect(error?.code == .snapshotUnavailable)
    #expect(revision == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsLateViewPublication() async throws {
    let controller = try projectViewController(
        document: .empty(named: "Older View")
    )
    let workspace = await ProjectWorkspace(project: controller)
    _ = try await workspace.evaluate()
    let olderState = try await controller.currentState()

    let newer = try await workspace.commit(
        ProjectSourceTransaction(
            name: "view.rename",
            commands: [.renameDocument(name: "Newer View")],
            expectedTransactionRevision: olderState.transactionRevision
        )
    )
    let retained = try await workspace.publish(olderState)
    let published = await workspace.view

    #expect(retained.publicationSequence == newer.publicationSequence)
    #expect(retained.projectName == "Newer View")
    #expect(published?.publicationSequence == newer.publicationSequence)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSavesAndLoadsWithoutAnInitialTargetView() async throws {
    try await withProjectViewTemporaryDirectory { directory in
        let sourceController = try projectViewController(
            document: try projectViewMeshOnlyDocument(named: "Saved View")
        )
        let sourceWorkspace = await ProjectWorkspace(project: sourceController)
        _ = try await sourceWorkspace.evaluate()
        let packageURL = directory.appendingPathComponent("saved.rupa")
        let saved = try await sourceWorkspace.save(to: packageURL)

        #expect(saved.isDirty == false)

        let targetController = try projectViewController(
            document: .empty(named: "Load Target")
        )
        let targetWorkspace = await ProjectWorkspace(project: targetController)
        #expect(await targetWorkspace.view?.projectName == nil)

        let loaded = try await targetWorkspace.load(from: packageURL)
        let item = try #require(loaded.viewport.items.first)

        #expect(loaded.projectName == "Saved View")
        #expect(loaded.viewport.items.count == 1)
        #expect(
            item.reference.providerID
                == GeometrySourceReference.authoredMeshProviderID
        )
        #expect(await targetWorkspace.view?.publicationSequence == loaded.publicationSequence)
    }
}

private func projectViewController(
    document: DesignDocument
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private func projectViewState(
    from state: ProjectStateSnapshot,
    evaluationSource: ProjectSourceModel? = nil,
    evaluation: EvaluatedProjectSnapshot? = nil
) -> ProjectStateSnapshot {
    ProjectStateSnapshot(
        document: state.document,
        package: state.package,
        documentGeneration: state.documentGeneration,
        transactionRevision: state.transactionRevision,
        publicationSequence: state.publicationSequence,
        isDirty: state.isDirty,
        canUndo: state.canUndo,
        canRedo: state.canRedo,
        selection: state.selection,
        workspaceState: state.workspaceState,
        evaluationSource: evaluationSource ?? state.evaluationSource,
        cadInteraction: state.cadInteraction,
        evaluation: evaluation ?? state.evaluation
    )
}

private func projectViewMeshOnlyDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let mesh = try projectViewTriangleMesh(identity: "mesh.view-only")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID = "representation.view-only"
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: projectViewRepresentationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    try document.validate()
    return document
}

private func projectViewCADAndMeshDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let bodyFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(
        object.geometryRepresentations.selection?.modeling
    )
    let mesh = try projectViewTriangleMesh(identity: "mesh.view-presentation")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID =
        "representation.view-presentation"
    document.authoredMeshAssets[asset.id] = asset
    object.geometryRepresentations.representations[meshRepresentationID] =
        GeometryRepresentation(
            id: meshRepresentationID,
            source: .authoredMesh(asset.id)
        )
    object.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = object
    try document.validate()
    return document
}

private func projectViewRepresentationSet(
    representationID: GeometryRepresentationID,
    source: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [
            representationID: GeometryRepresentation(
                id: representationID,
                source: source
            ),
        ],
        selection: GeometryRepresentationSelection(
            modeling: representationID,
            presentation: representationID
        )
    )
}

private func projectViewTriangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func expectProjectViewSharedStorage(
    _ evaluated: MeshSource,
    _ source: MeshSource
) {
    #expect(
        evaluated.vertexPositions.storage.chunkIdentities
            == source.vertexPositions.storage.chunkIdentities
    )
    #expect(
        evaluated.vertexPositions.storage.pageIdentities
            == source.vertexPositions.storage.pageIdentities
    )
    #expect(
        evaluated.faceIDs.storage.chunkIdentities
            == source.faceIDs.storage.chunkIdentities
    )
    #expect(
        evaluated.cornerVertexIDs.storage.chunkIdentities
            == source.cornerVertexIDs.storage.chunkIdentities
    )
}

private func withProjectViewTemporaryDirectory<Result: Sendable>(
    _ body: (URL) async throws -> Result
) async throws -> Result {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-project-view-tests-\(UUID().uuidString)",
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
            throw ProjectViewSnapshotError(
                code: .sourceMismatch,
                message: "Test failed and temporary cleanup also failed: "
                    + "\(primaryError); \(cleanupError)."
            )
        }
        throw primaryError
    }
}
