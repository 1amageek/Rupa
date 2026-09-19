import RupaCore
import RupaCoreTypes
import RupaProject
import Testing
@testable import RupaKit

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectOutlinerRenamePublishesSourceNamesAndSupportsUndoRedo() async throws {
    var document = DesignDocument.empty(named: "Outliner")
    let rootID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    let definitionID = try document.createComponentDefinition(name: "Shared Part")
    let instanceID = try document.createComponentInstance(name: "Original Instance", definitionID: definitionID)
    let instanceNodeID = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.componentInstanceID == instanceID
    }?.id)
    let controller = try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: controller)
    let base = try await workspace.evaluate()
    let sourceBefore = try await controller.currentState().evaluationSource
    let action = try DefaultProjectWorkspaceActionPlanner().source(
        name: "outliner.rename",
        commands: [
            .renameSceneNode(id: rootID, name: " Assembly "),
            .renameComponentInstance(id: instanceID, name: " Housing "),
        ], from: base
    )
    _ = try await workspace.perform(action)
    let renamed = try #require(workspace.view)
    #expect(renamed.document.document.productMetadata.sceneNodes[rootID]?.name == "Assembly")
    #expect(renamed.document.document.productMetadata.sceneNodes[instanceNodeID]?.name == "Housing")
    #expect(renamed.document.document.productMetadata.componentInstances[instanceID]?.name == "Housing")
    #expect(renamed.transactionRevision.value == base.transactionRevision.value + 1)
    let sourceAfter = try await controller.currentState().evaluationSource
    #expect(sourceAfter.occurrences == sourceBefore.occurrences)
    #expect(Set(sourceAfter.objectDefinitions.keys) == Set(sourceBefore.objectDefinitions.keys))
    #expect(sourceAfter.objectDefinitions.values.contains { $0.name == "Housing" })
    #expect(sourceAfter.objectDefinitions.values.contains { $0.name == "Assembly" })
    let undone = try await workspace.undo()
    #expect(undone.document.document.productMetadata == document.productMetadata)
    #expect(!undone.canUndo)
    let redone = try await workspace.redo()
    #expect(redone.document.document.productMetadata == renamed.document.document.productMetadata)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func projectOutlinerBatchIsAtomicAndRejectsStalePublication() async throws {
    let document = DesignDocument.empty(named: "Outliner Batch")
    let rootID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    let controller = try ProjectController(
        document: document,
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: controller)
    let base = try await workspace.evaluate()
    let planner = DefaultProjectWorkspaceActionPlanner()
    let rejected = try planner.source(name: "outliner.invalidBatch", commands: [
        .setSceneNodeVisibility(id: rootID, isVisible: false),
        .setSceneNodeLock(id: SceneNodeID(), isLocked: true),
    ], from: base)
    await #expect(throws: Error.self) { _ = try await workspace.perform(rejected) }
    let unchanged = try #require(workspace.view)
    #expect(unchanged.publicationSequence == base.publicationSequence)
    #expect(unchanged.document.document.productMetadata == document.productMetadata)
    #expect(!unchanged.canUndo)

    let batch = try planner.source(name: "outliner.stateBatch", commands: [
        .setSceneNodeVisibility(id: rootID, isVisible: false),
        .setSceneNodeLock(id: rootID, isLocked: true),
    ], from: base)
    _ = try await workspace.perform(batch)
    let applied = try #require(workspace.view)
    #expect(applied.document.document.productMetadata.sceneNodes[rootID]?.isVisible == false)
    #expect(applied.document.document.productMetadata.sceneNodes[rootID]?.isLocked == true)
    #expect(applied.transactionRevision.value == base.transactionRevision.value + 1)
    await #expect(throws: Error.self) { _ = try await workspace.perform(batch) }
    #expect(workspace.view?.publicationSequence == applied.publicationSequence)
    let undone = try await workspace.undo()
    #expect(undone.document.document.productMetadata == document.productMetadata)
    #expect(!undone.canUndo)
}
