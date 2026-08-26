import Foundation
import RupaCADIntegration
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProject
import RupaProjectModel
import RupaProjectPackage
import Synchronization
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
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
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
func projectWorkspaceReturnsTheExactSourceViewWithoutRegressingNewerPublication() async throws {
    let controller = try projectViewController(
        document: .empty(named: "Initial")
    )
    let gate = NthProjectViewBuildGate(blockedBuildNumber: 2)
    defer { gate.release() }
    let workspace = await ProjectWorkspace(
        project: controller,
        viewBuilder: GatedProjectViewSnapshotBuilder(gate: gate)
    )
    let initial = try await workspace.evaluate()
    let firstTransaction = try ProjectSourceTransaction(
        name: "view.first-exact-result",
        commands: [.renameDocument(name: "First")],
        expectedProjectID: await controller.currentDocument().projectID,
        expectedTransactionRevision: initial.transactionRevision,
        expectedPublicationSequence: initial.publicationSequence
    )

    let firstTask = Task {
        try await workspace.perform(.source(firstTransaction))
    }
    while !gate.didBlock {
        await Task.yield()
    }

    let firstState = try await controller.currentState()
    let secondCommit = try await controller.commit(
        ProjectSourceTransaction(
            name: "view.second-newer-result",
            commands: [.renameDocument(name: "Second")],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: firstState.transactionRevision,
            expectedPublicationSequence: firstState.publicationSequence
        )
    )
    let secondView = try await workspace.publish(secondCommit.state)
    gate.release()

    let firstResult = try await firstTask.value
    guard case .source(let firstCommit, let firstView) = firstResult else {
        Issue.record("The first source action must preserve its source result.")
        return
    }
    let published = try #require(await workspace.view)

    #expect(firstCommit.state.publicationSequence == firstView.publicationSequence)
    #expect(
        firstCommit.state.document.cadDocument.metadata.name
            == firstView.document.name
    )
    #expect(firstCommit.state.transactionRevision == firstView.transactionRevision)
    #expect(firstCommit.state.evaluation.id.sourceRevision == firstView.transactionRevision)
    #expect(secondView.publicationSequence > firstView.publicationSequence)
    #expect(published.publicationSequence == secondView.publicationSequence)
    #expect(published.document.name == "Second")
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
func projectStateAndViewSnapshotsRetainInjectedRegistryAndEvaluationSnapshot() async throws {
    let customTypeID: ObjectTypeID = "custom.snapshot-registry"
    let registry = try ObjectTypeRegistry(
        definitions: [
            ObjectTypeDefinition(
                id: customTypeID,
                title: "Snapshot Registry Type",
                systemImage: "circle",
                representation: .twoDimensional,
                category: .annotation
            ),
        ]
    )
    let controller = try projectViewController(
        document: .empty(named: "Injected Registry"),
        objectRegistry: registry
    )
    let workspace = await ProjectWorkspace(project: controller)
    let view = try await workspace.evaluate()
    let state = try await controller.currentState()

    #expect(state.objectRegistry.definitions == registry.definitions)
    #expect(view.objectRegistry.definitions == registry.definitions)
    #expect(view.evaluationSnapshot == state.evaluationSnapshot)
    #expect(view.publicationSequence == state.publicationSequence)
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
        documentLifetimeID: state.documentLifetimeID,
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
        objectRegistry: state.objectRegistry,
        evaluationSnapshot: state.evaluationSnapshot,
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
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: DocumentTransactionRevision(0),
            expectedPublicationSequence: 0
        )
    )
    let state = try await controller.currentState()
    _ = try #require(state.cadInteraction)
    let mismatched = ProjectStateSnapshot(
        documentLifetimeID: state.documentLifetimeID,
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
        objectRegistry: state.objectRegistry,
        evaluationSnapshot: state.evaluationSnapshot,
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
    var error: ProjectWorkspaceActionError?

    do {
        _ = try await workspace.undo()
    } catch let caught as ProjectWorkspaceActionError {
        error = caught
    }
    let revision = await controller.currentTransactionRevision()

    #expect(error?.code == .snapshotUnavailable)
    #expect(revision == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceReturnsLateExactViewWithoutRegressingPublication() async throws {
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
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: olderState.transactionRevision,
            expectedPublicationSequence: olderState.publicationSequence
        )
    )
    let retained = try await workspace.publish(olderState)
    let published = await workspace.view

    #expect(retained.publicationSequence == olderState.publicationSequence)
    #expect(retained.projectName == "Older View")
    #expect(published?.publicationSequence == newer.publicationSequence)
    #expect(published?.projectName == "Newer View")
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

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceSameProjectIDLoadChangesDocumentLifetime() async throws {
    try await withProjectViewTemporaryDirectory { directory in
        let original = try projectViewMeshOnlyDocument(named: "Before Reload")
        let sourceController = try projectViewController(document: original)
        let sourceWorkspace = await ProjectWorkspace(project: sourceController)
        let sourceInitial = try await sourceWorkspace.evaluate()
        let renamed = try await sourceWorkspace.commit(
            ProjectSourceTransaction(
                name: "view.prepare-same-project-reload",
                commands: [.renameDocument(name: "After Reload")],
                expectedProjectID: sourceInitial.projectID,
                expectedTransactionRevision: sourceInitial.transactionRevision,
                expectedPublicationSequence: sourceInitial.publicationSequence
            )
        )
        #expect(renamed.documentLifetimeID == sourceInitial.documentLifetimeID)
        let packageURL = directory.appendingPathComponent("same-project.rupa")
        _ = try await sourceWorkspace.save(to: packageURL)

        let targetController = try projectViewController(document: original)
        let targetWorkspace = await ProjectWorkspace(project: targetController)
        let visibleBeforeLoad = try await targetWorkspace.evaluate()
        let loaded = try await targetWorkspace.load(from: packageURL)

        #expect(loaded.projectID == visibleBeforeLoad.projectID)
        #expect(loaded.projectName == "After Reload")
        #expect(loaded.documentLifetimeID != visibleBeforeLoad.documentLifetimeID)
        #expect(await targetWorkspace.view?.documentLifetimeID == loaded.documentLifetimeID)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceReplacesProjectAuthorityWithoutReplacingTheWorkspace() async throws {
    let controller = try projectViewController(document: .empty(named: "Original"))
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let replacementDocument = try projectViewMeshOnlyDocument(named: "Replacement")

    let replacement = try await workspace.replace(with: replacementDocument)
    let item = try #require(replacement.viewport.items.first)
    let source = try #require(
        replacement.document.document.authoredMeshAssets.values.first?.source
    )

    #expect(replacement.projectID == replacementDocument.projectID)
    #expect(replacement.projectID != initial.projectID)
    #expect(replacement.documentLifetimeID != initial.documentLifetimeID)
    #expect(replacement.transactionRevision == DocumentTransactionRevision(1))
    #expect(replacement.publicationSequence == initial.publicationSequence + 1)
    #expect(replacement.projectName == "Replacement")
    #expect(replacement.canUndo == false)
    #expect(replacement.canRedo == false)
    expectProjectViewSharedStorage(item.mesh, source)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceInitialLoadRejectsAConcurrentAuthorityPublication() async throws {
    let loadedDocument = try projectViewMeshOnlyDocument(named: "Loaded Without View")
    let sourceController = try projectViewController(document: loadedDocument)
    let loadedPackage = await sourceController.currentPackage()
    let gate = ProjectPackageLoadGate()
    let controller = try ProjectController(
        document: .empty(named: "Retained Without View"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        packageReader: BlockingProjectPackageReader(
            package: loadedPackage,
            gate: gate
        )
    )
    let workspace = await ProjectWorkspace(project: controller)

    let load = Task {
        try await workspace.load(
            from: URL(fileURLWithPath: "/ignored/initial-load-race.rupa")
        )
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    _ = try await controller.evaluateCurrent(operationGuard: {})
    gate.release()

    var loadError: ProjectControllerError?
    do {
        _ = try await load.value
    } catch let caught as ProjectControllerError {
        loadError = caught
    }
    let retained = try await controller.currentState()

    #expect(loadError?.code == .publicationConflict)
    #expect(retained.document.cadDocument.metadata.name == "Retained Without View")
    #expect(retained.publicationSequence == 1)
    #expect(await workspace.view == nil)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspacePublishesAtomicInteractionWithoutSourceRevisionOrEvaluation() async throws {
    let document = try projectViewMeshOnlyDocument(named: "Interaction View")
    let probe = ProjectInteractionEvaluationProbe()
    let controller = try ProjectController(
        document: document,
        evaluatorPreparer: ProjectInteractionCountingPreparer(probe: probe),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let sourceMesh = try #require(initial.document.document.authoredMeshAssets.values.first?.source)
    let sceneNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.object != nil
    }?.key)
    let selection = SelectionModel(
        selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)]
    )

    let published = try await workspace.applyInteraction(
        try ProjectInteractionTransaction(
            selection: .replace(selection),
            workspaceCommands: [
                .setViewportGridSettings(
                    ViewportGridSettings(visualSpacingMode: .fixed)
                ),
            ],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
        )
    )

    #expect(published.selection == selection)
    #expect(published.workspaceState.viewportGridSettings.visualSpacingMode == .fixed)
    #expect(published.workspaceState.revision == WorkspaceRevision(1))
    #expect(published.transactionRevision == initial.transactionRevision)
    #expect(published.documentGeneration == initial.documentGeneration)
    #expect(published.publicationSequence == initial.publicationSequence + 1)
    #expect(published.viewport.snapshotID == initial.viewport.snapshotID)
    #expect(probe.evaluationCount == 1)

    let publishedMesh = try #require(published.viewport.items.first?.mesh)
    expectProjectViewSharedStorage(publishedMesh, sourceMesh)
    var callerOwnedDocument = published.document.document
    callerOwnedDocument.rename("Caller Mutation")
    #expect(published.document.name == "Interaction View")
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsInvalidInteractionWithoutPublicationOrPartialState() async throws {
    let document = try projectViewMeshOnlyDocument(named: "Interaction Failure")
    let controller = try projectViewController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let initialState = try await controller.currentState()
    let initialSourceMesh = try #require(
        initialState.document.authoredMeshAssets.values.first?.source
    )
    let initialEvaluatedMesh = try #require(
        initialState.evaluation.occurrences.values.first?.mesh
    )
    let sceneNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.object != nil
    }?.key)
    let selection = SelectionModel(
        selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)]
    )
    let invalidPlane = ConstructionPlaneSourceID()
    var error: ProjectControllerError?

    do {
        _ = try await workspace.applyInteraction(
            try ProjectInteractionTransaction(
                selection: .replace(selection),
                workspaceCommands: [
                    .setViewportGridSettings(
                        ViewportGridSettings(visualSpacingMode: .fixed)
                    ),
                    .setActiveConstructionPlane(invalidPlane),
                ],
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: initial.transactionRevision,
                expectedPublicationSequence: initial.publicationSequence
            )
        )
    } catch let caught as ProjectControllerError {
        error = caught
    }

    let retained = try #require(await workspace.view)
    #expect(error?.code == .transactionInvalid)
    #expect(retained.selection == initial.selection)
    #expect(retained.workspaceState.revision == initial.workspaceState.revision)
    #expect(retained.workspaceState.viewportGridSettings == initial.workspaceState.viewportGridSettings)
    #expect(retained.workspaceState.ruler == initial.workspaceState.ruler)
    #expect(retained.transactionRevision == initial.transactionRevision)
    #expect(retained.publicationSequence == initial.publicationSequence)

    let retainedState = try await controller.currentState()
    #expect(retainedState.selection == initialState.selection)
    #expect(retainedState.workspaceState.revision == initialState.workspaceState.revision)
    #expect(
        retainedState.workspaceState.viewportGridSettings
            == initialState.workspaceState.viewportGridSettings
    )
    #expect(retainedState.workspaceState.ruler == initialState.workspaceState.ruler)
    #expect(retainedState.transactionRevision == initialState.transactionRevision)
    #expect(retainedState.documentGeneration == initialState.documentGeneration)
    #expect(retainedState.publicationSequence == initialState.publicationSequence)
    #expect(retainedState.evaluation.id == initialState.evaluation.id)
    #expect(
        retainedState.evaluation.copyTelemetry
            == initialState.evaluation.copyTelemetry
    )
    let retainedEvaluatedMesh = try #require(
        retainedState.evaluation.occurrences.values.first?.mesh
    )
    expectProjectViewSharedStorage(retainedEvaluatedMesh, initialEvaluatedMesh)
    expectProjectViewSharedStorage(retainedEvaluatedMesh, initialSourceMesh)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceDoesNotPublishSemanticWorkspaceNoOps() async throws {
    let document = try projectViewMeshOnlyDocument(named: "Workspace No Op")
    let controller = try projectViewController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()

    let sameValue = try await workspace.applyWorkspace(
        .setViewportGridSettings(.standard)
    )
    #expect(sameValue.publicationSequence == initial.publicationSequence)
    #expect(sameValue.workspaceState.revision == initial.workspaceState.revision)
    #expect(
        sameValue.workspaceState.viewportGridSettings
            == initial.workspaceState.viewportGridSettings
    )

    let sceneNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.object != nil
    }?.key)
    let selected = SelectionModel(
        selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)]
    )
    let selectionWithSameValueWorkspace = try await workspace.applyInteraction(
        try ProjectInteractionTransaction(
            selection: .replace(selected),
            workspaceCommands: [.setViewportGridSettings(.standard)],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
        )
    )
    #expect(selectionWithSameValueWorkspace.selection == selected)
    #expect(
        selectionWithSameValueWorkspace.workspaceState.revision
            == initial.workspaceState.revision
    )
    #expect(
        selectionWithSameValueWorkspace.workspaceState.viewportGridSettings
            == initial.workspaceState.viewportGridSettings
    )
    #expect(
        selectionWithSameValueWorkspace.publicationSequence
            == initial.publicationSequence + 1
    )

    let changeThenRevert = try await workspace.applyWorkspace([
        .setViewportGridSettings(
            ViewportGridSettings(visualSpacingMode: .fixed)
        ),
        .setViewportGridSettings(.standard),
    ])
    #expect(
        changeThenRevert.publicationSequence
            == selectionWithSameValueWorkspace.publicationSequence
    )
    #expect(changeThenRevert.workspaceState.revision == initial.workspaceState.revision)
    #expect(
        changeThenRevert.workspaceState.viewportGridSettings
            == initial.workspaceState.viewportGridSettings
    )

    let selectionWithNetZeroWorkspace = try await workspace.applyInteraction(
        try ProjectInteractionTransaction(
            selection: .clear,
            workspaceCommands: [
                .setViewportGridSettings(
                    ViewportGridSettings(visualSpacingMode: .fixed)
                ),
                .setViewportGridSettings(.standard),
            ],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: selectionWithSameValueWorkspace.publicationSequence
        )
    )
    #expect(selectionWithNetZeroWorkspace.selection == initial.selection)
    #expect(
        selectionWithNetZeroWorkspace.workspaceState.revision
            == initial.workspaceState.revision
    )
    #expect(
        selectionWithNetZeroWorkspace.workspaceState.viewportGridSettings
            == initial.workspaceState.viewportGridSettings
    )
    #expect(
        selectionWithNetZeroWorkspace.publicationSequence
            == selectionWithSameValueWorkspace.publicationSequence + 1
    )
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsLoadThatRacesWithInteractionPublication() async throws {
    let loadedDocument = try projectViewMeshOnlyDocument(named: "Loaded During Interaction")
    let sourceController = try projectViewController(document: loadedDocument)
    let loadedPackage = await sourceController.currentPackage()
    let gate = ProjectPackageLoadGate()
    let controller = try ProjectController(
        document: try projectViewMeshOnlyDocument(named: "Retained During Load"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        packageReader: BlockingProjectPackageReader(
            package: loadedPackage,
            gate: gate
        )
    )
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let initialState = try await controller.currentState()
    let initialSourceMesh = try #require(
        initialState.document.authoredMeshAssets.values.first?.source
    )
    let sceneNodeID = try #require(initial.document.document.productMetadata.sceneNodes.first {
        $0.value.object != nil
    }?.key)
    let selection = SelectionModel(
        selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)]
    )

    let load = Task {
        try await workspace.load(
            from: URL(fileURLWithPath: "/ignored/load-race.rupa")
        )
    }
    while !gate.didStart {
        try await Task.sleep(for: .milliseconds(1))
    }
    defer { gate.release() }

    let interaction = try await workspace.applyInteraction(
        try ProjectInteractionTransaction(
            selection: .replace(selection),
            workspaceCommands: [
                .setViewportGridSettings(
                    ViewportGridSettings(visualSpacingMode: .fixed)
                ),
            ],
            expectedProjectID: await controller.currentDocument().projectID,
            expectedTransactionRevision: initial.transactionRevision,
            expectedPublicationSequence: initial.publicationSequence
        )
    )
    gate.release()

    var loadError: ProjectControllerError?
    do {
        _ = try await load.value
    } catch let caught as ProjectControllerError {
        loadError = caught
    }

    let retainedView = try #require(await workspace.view)
    let retainedState = try await controller.currentState()
    #expect(loadError?.code == .publicationConflict)
    #expect(retainedView.selection == interaction.selection)
    expectProjectViewWorkspaceStateEqual(
        retainedView.workspaceState,
        interaction.workspaceState
    )
    #expect(retainedView.publicationSequence == interaction.publicationSequence)
    #expect(retainedState.selection == interaction.selection)
    expectProjectViewWorkspaceStateEqual(
        retainedState.workspaceState,
        interaction.workspaceState
    )
    #expect(retainedState.transactionRevision == initialState.transactionRevision)
    #expect(retainedState.documentGeneration == initialState.documentGeneration)
    #expect(retainedState.publicationSequence == interaction.publicationSequence)
    #expect(retainedState.evaluation.id == initialState.evaluation.id)
    #expect(
        retainedState.evaluation.copyTelemetry
            == initialState.evaluation.copyTelemetry
    )
    let retainedEvaluatedMesh = try #require(
        retainedState.evaluation.occurrences.values.first?.mesh
    )
    expectProjectViewSharedStorage(retainedEvaluatedMesh, initialSourceMesh)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceDoesNotPublishSelectionNoOpOrAcceptHoverAuthority() async throws {
    let document = try projectViewMeshOnlyDocument(named: "Interaction No Op")
    let controller = try projectViewController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()

    let noOp = try await workspace.applySelection(.replace(.empty))
    #expect(noOp.publicationSequence == initial.publicationSequence)

    var hovered = SelectionModel.empty
    let sceneNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.object != nil
    }?.key)
    try hovered.hoverSceneNode(sceneNodeID, in: document)
    var error: ProjectControllerError?
    do {
        _ = try await workspace.applySelection(.replace(hovered))
    } catch let caught as ProjectControllerError {
        error = caught
    }
    let retained = try #require(await workspace.view)
    #expect(error?.code == .transactionInvalid)
    #expect(retained.publicationSequence == initial.publicationSequence)
    #expect(retained.selection == initial.selection)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsInteractionFromStaleSourceRevision() async throws {
    let controller = try projectViewController(
        document: try projectViewMeshOnlyDocument(named: "Stale Source Revision")
    )
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let staleRevision = try initial.transactionRevision.advanced()
    let sceneNodeID = try #require(initial.document.document.productMetadata.sceneNodes.first {
        $0.value.object != nil
    }?.key)
    var error: ProjectControllerError?

    do {
        _ = try await workspace.applyInteraction(
            try ProjectInteractionTransaction(
                selection: .replace(
                    SelectionModel(
                        selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)]
                    )
                ),
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: staleRevision,
                expectedPublicationSequence: initial.publicationSequence
            )
        )
    } catch let caught as ProjectControllerError {
        error = caught
    }

    let retained = try #require(await workspace.view)
    #expect(error?.code == .revisionConflict)
    #expect(retained.transactionRevision == initial.transactionRevision)
    #expect(retained.publicationSequence == initial.publicationSequence)
    #expect(retained.selection == initial.selection)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsInteractionFromStalePublicationSequence() async throws {
    let controller = try projectViewController(
        document: try projectViewMeshOnlyDocument(named: "Stale Publication")
    )
    let workspace = await ProjectWorkspace(project: controller)
    let initial = try await workspace.evaluate()
    let current = try await workspace.applyWorkspace(
        .setViewportGridSettings(
            ViewportGridSettings(visualSpacingMode: .fixed)
        )
    )
    let sceneNodeID = try #require(initial.document.document.productMetadata.sceneNodes.first {
        $0.value.object != nil
    }?.key)
    var error: ProjectControllerError?

    do {
        _ = try await workspace.applyInteraction(
            try ProjectInteractionTransaction(
                selection: .replace(
                    SelectionModel(
                        selectedTargets: [SelectionTarget(sceneNodeID: sceneNodeID)]
                    )
                ),
                expectedProjectID: await controller.currentDocument().projectID,
                expectedTransactionRevision: initial.transactionRevision,
                expectedPublicationSequence: initial.publicationSequence
            )
        )
    } catch let caught as ProjectControllerError {
        error = caught
    }

    let retained = try #require(await workspace.view)
    #expect(error?.code == .publicationConflict)
    #expect(retained.transactionRevision == current.transactionRevision)
    #expect(retained.publicationSequence == current.publicationSequence)
    #expect(retained.selection == current.selection)
    #expect(retained.workspaceState.viewportGridSettings.visualSpacingMode == .fixed)
}

private func projectViewController(
    document: DesignDocument,
    objectRegistry: ObjectTypeRegistry = .builtIn
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge(),
        objectRegistry: objectRegistry
    )
}

private final class ProjectInteractionEvaluationProbe: Sendable {
    private let count = Mutex(0)

    var evaluationCount: Int {
        count.withLock { $0 }
    }

    func recordEvaluation() {
        count.withLock { $0 += 1 }
    }
}

private struct ProjectInteractionCountingPreparer: ProjectEvaluatorPreparing {
    let probe: ProjectInteractionEvaluationProbe
    private let base = DefaultDesignDocumentProjectEvaluatorFactory()

    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        let evaluator = try base.makeEvaluator(
            for: document,
            reusing: currentEvaluation
        )
        return ProjectInteractionCountingEvaluator(
            base: evaluator,
            probe: probe
        )
    }
}

private struct ProjectInteractionCountingEvaluator: ProjectEvaluating {
    let base: any ProjectEvaluating
    let probe: ProjectInteractionEvaluationProbe

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        probe.recordEvaluation()
        return try base.evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}

private final class ProjectPackageLoadGate: Sendable {
    private struct State {
        var didStart = false
        var isReleased = false
    }

    private let state = Mutex(State())

    var didStart: Bool {
        state.withLock { $0.didStart }
    }

    func markStarted() {
        state.withLock { $0.didStart = true }
    }

    func waitUntilReleased() {
        while !state.withLock({ $0.isReleased }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.isReleased = true }
    }
}

private final class NthProjectViewBuildGate: Sendable {
    private struct State {
        var buildCount = 0
        var didBlock = false
        var isReleased = false
    }

    private let state = Mutex(State())
    private let blockedBuildNumber: Int

    init(blockedBuildNumber: Int) {
        self.blockedBuildNumber = blockedBuildNumber
    }

    var didBlock: Bool {
        state.withLock { $0.didBlock }
    }

    func waitIfNeeded() {
        let shouldBlock = state.withLock { state in
            state.buildCount += 1
            guard state.buildCount == blockedBuildNumber else {
                return false
            }
            state.didBlock = true
            return true
        }
        guard shouldBlock else {
            return
        }
        while !state.withLock({ $0.isReleased }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func release() {
        state.withLock { $0.isReleased = true }
    }
}

private struct GatedProjectViewSnapshotBuilder: ProjectViewSnapshotBuilding {
    let gate: NthProjectViewBuildGate

    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot {
        gate.waitIfNeeded()
        return try ProjectViewSnapshotBuilder().build(from: state)
    }
}

private struct BlockingProjectPackageReader: ProjectPackageReading {
    let package: ProjectPackageDocument
    let gate: ProjectPackageLoadGate

    func load(from _: URL) throws -> ProjectPackageDocument {
        gate.markStarted()
        gate.waitUntilReleased()
        return package
    }
}

private func projectViewState(
    from state: ProjectStateSnapshot,
    evaluationSource: ProjectSourceModel? = nil,
    evaluation: EvaluatedProjectSnapshot? = nil
) -> ProjectStateSnapshot {
    ProjectStateSnapshot(
        documentLifetimeID: state.documentLifetimeID,
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
        objectRegistry: state.objectRegistry,
        evaluationSnapshot: state.evaluationSnapshot,
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

private func expectProjectViewWorkspaceStateEqual(
    _ lhs: WorkspaceState,
    _ rhs: WorkspaceState
) {
    #expect(lhs.revision == rhs.revision)
    #expect(lhs.ruler == rhs.ruler)
    #expect(lhs.viewportGridSettings == rhs.viewportGridSettings)
    #expect(lhs.activeConstructionPlaneID == rhs.activeConstructionPlaneID)
    #expect(lhs.curveCurvatureDisplays == rhs.curveCurvatureDisplays)
    #expect(lhs.pointDisplays == rhs.pointDisplays)
    #expect(lhs.surfaceControlPointDisplays == rhs.surfaceControlPointDisplays)
    #expect(lhs.surfaceFrameDisplays == rhs.surfaceFrameDisplays)
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
