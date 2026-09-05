import RupaCore
import RupaCoreTypes
import RupaProject
import RupaKit
import Testing

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceStagesHistoryReorderAndRejectsStaleAction() async throws {
    let controller = try makeHistoryController(document: try makeIndependentSketchDocument())
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let originalOrder = snapshot.document.document.cadDocument.designGraph.order
    let reordered = Array(originalOrder.reversed())
    let planner = DefaultProjectWorkspaceActionPlanner()
    let action = try planner.source(
        name: "history.reorder",
        commands: [.reorderFeatureGraph(featureIDs: reordered)],
        from: snapshot
    )

    let preview = try await workspace.preview(action)
    guard case .source(let sourcePreview) = preview else {
        Issue.record("History reorder must use the source preview route.")
        return
    }
    #expect(sourcePreview.wouldMutate)
    let beforeCommit = try await controller.currentState()
    #expect(beforeCommit.document.cadDocument.designGraph.order == originalOrder)
    #expect(beforeCommit.transactionRevision == snapshot.transactionRevision)

    _ = try await workspace.perform(action)
    let committed = try #require(await workspace.view)
    #expect(committed.document.document.cadDocument.designGraph.order == reordered)
    #expect(committed.transactionRevision.value == snapshot.transactionRevision.value + 1)
    #expect(committed.documentGeneration.value == snapshot.documentGeneration.value + 1)
    #expect(committed.canUndo)

    let staleAction = try planner.source(
        name: "history.stale-reorder",
        commands: [.reorderFeatureGraph(featureIDs: originalOrder)],
        from: snapshot
    )
    var staleError: ProjectControllerError?
    do {
        _ = try await workspace.perform(staleAction)
    } catch let error as ProjectControllerError {
        staleError = error
    }
    #expect(staleError?.code == .revisionConflict)

    let retained = try await controller.currentState()
    #expect(retained.document.cadDocument.designGraph.order == reordered)
    #expect(retained.transactionRevision == committed.transactionRevision)
    #expect(retained.publicationSequence == committed.publicationSequence)

    let undone = try await workspace.undo(from: committed)
    #expect(undone.document.document.cadDocument.designGraph.order == originalOrder)
    let redone = try await workspace.redo(from: undone)
    #expect(redone.document.document.cadDocument.designGraph.order == reordered)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceRejectsDependencyUnsafeHistoryReorderAtomically() async throws {
    let document = try makeDependentSketchDocument()
    let controller = try makeHistoryController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let originalOrder = snapshot.document.document.cadDocument.designGraph.order
    let invalidOrder = Array(originalOrder.reversed())
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "history.invalid-reorder",
        commands: [.reorderFeatureGraph(featureIDs: invalidOrder)],
        from: snapshot
    )

    var error: ProjectControllerError?
    do {
        _ = try await workspace.perform(action)
    } catch let caught as ProjectControllerError {
        error = caught
    }
    #expect(error?.code == .transactionInvalid)

    let retained = try await controller.currentState()
    #expect(retained.document.cadDocument.designGraph.order == originalOrder)
    #expect(retained.documentGeneration == snapshot.documentGeneration)
    #expect(retained.transactionRevision == snapshot.transactionRevision)
    #expect(retained.publicationSequence == snapshot.publicationSequence)
    #expect(!retained.canUndo)
    #expect(!retained.canRedo)
}

@Test(.timeLimit(.minutes(1)))
func projectWorkspaceStagesSuppressionAndParameterHistoryAsOneSourceEntry() async throws {
    let document = try makeIndependentSketchDocument()
    let featureID = try #require(document.cadDocument.designGraph.order.first)
    let controller = try makeHistoryController(document: document)
    let workspace = await ProjectWorkspace(project: controller)
    let snapshot = try await workspace.evaluate()
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "history.suppression-and-parameter",
        commands: [
            .setFeatureSuppression(featureID: featureID, isSuppressed: true),
            .upsertParameter(
                name: "clearance",
                expression: .constant(.length(1.0, unit: .millimeter)),
                kind: .length
            ),
        ],
        from: snapshot
    )

    let result = try await workspace.perform(action)
    guard case .source(let commit, let committed) = result else {
        Issue.record("History source commands must publish a source result.")
        return
    }
    let suppressed = try #require(
        committed.document.document.cadDocument.designGraph.nodes[featureID]
    )
    #expect(commit.commandResults.count == 2)
    #expect(suppressed.isSuppressed)
    #expect(
        committed.document.document.cadDocument.parameterID(named: "clearance") != nil
    )
    #expect(committed.canUndo)

    let undone = try await workspace.undo(from: committed)
    let restored = try #require(
        undone.document.document.cadDocument.designGraph.nodes[featureID]
    )
    #expect(!restored.isSuppressed)
    #expect(undone.document.document.cadDocument.parameterID(named: "clearance") == nil)

    let redone = try await workspace.redo(from: undone)
    let reapplied = try #require(
        redone.document.document.cadDocument.designGraph.nodes[featureID]
    )
    #expect(reapplied.isSuppressed)
    #expect(redone.document.document.cadDocument.parameterID(named: "clearance") != nil)
}

private func makeHistoryController(document: DesignDocument) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
}

private func makeIndependentSketchDocument() throws -> DesignDocument {
    let store = CADDocumentStore()
    let commandStack = CommandStack()
    _ = try commandStack.execute(
        .createRectangleSketch(
            name: "First",
            plane: .xy,
            width: .length(8.0, .millimeter),
            height: .length(4.0, .millimeter)
        ),
        in: store
    )
    _ = try commandStack.execute(
        .createRectangleSketch(
            name: "Second",
            plane: .xy,
            width: .length(6.0, .millimeter),
            height: .length(3.0, .millimeter)
        ),
        in: store
    )
    return store.document
}

private func makeDependentSketchDocument() throws -> DesignDocument {
    let store = CADDocumentStore()
    let commandStack = CommandStack()
    _ = try commandStack.execute(
        .createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .length(8.0, .millimeter),
            height: .length(4.0, .millimeter)
        ),
        in: store
    )
    let profileID = try #require(store.document.cadDocument.designGraph.order.first)
    _ = try commandStack.execute(
        .extrudeProfile(
            name: "Body",
            profile: ProfileReference(featureID: profileID),
            distance: .length(2.0, .millimeter),
            direction: .normal
        ),
        in: store
    )
    return store.document
}
