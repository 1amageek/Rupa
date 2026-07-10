import SwiftCAD
import Testing
import RupaCore
@testable import RupaAutomation

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationBatchResolvesHomogeneousEffects() async throws {
    #expect(try AutomationBatch(commands: []).validatedEffect() == .readOnly)
    #expect(
        try AutomationBatch(
            commands: [.describeDocument, .validateDocument]
        ).validatedEffect() == .readOnly
    )
    #expect(
        try AutomationBatch(
            commands: [.describeDocument, .renameDocument(name: "Source")]
        ).validatedEffect() == .sourceMutation
    )
    #expect(
        try AutomationBatch(
            commands: [.describeDocument, .setDisplayUnit(.meter)]
        ).validatedEffect() == .workspaceMutation
    )
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationBatchRejectsMixedMutationEffectsBeforePublication() async throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let originalStore = session.store
    let originalCommandStack = session.commandStack
    var caught: EditorError?

    do {
        _ = try AutomationRunner().executeBatch(
            AutomationBatch(
                commands: [
                    .renameDocument(name: "Never Committed"),
                    .setDisplayUnit(.meter),
                ]
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("cannot mix") == true)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationWorkspaceBatchCommitsAtomicallyWithoutDirtyingSource() async throws {
    let session = EditorSession()
    let originalStore = session.store
    let originalCommandStack = session.commandStack
    let batch = AutomationBatch(
        commands: [
            .setDisplayUnit(.meter),
            .describeDocument,
            .setViewportGridSettings(
                ViewportGridSettings(visualSpacingMode: .fixed)
            ),
        ],
        expectedGeneration: DocumentGeneration(0),
        expectedWorkspaceRevision: WorkspaceRevision(0)
    )

    let execution = try AutomationRunner().executeBatchTransaction(
        batch,
        in: session,
        commits: true
    )

    #expect(execution.effect == .workspaceMutation)
    #expect(execution.baseGeneration == DocumentGeneration(0))
    #expect(execution.proposedGeneration == DocumentGeneration(0))
    #expect(execution.baseWorkspaceRevision == WorkspaceRevision(0))
    #expect(execution.proposedWorkspaceRevision == WorkspaceRevision(2))
    #expect(execution.didCommit)
    #expect(execution.results.map(\.effect) == [.workspaceMutation, .readOnly, .workspaceMutation])
    #expect(execution.results[1].message.contains("m display units"))
    #expect(session.workspaceState.displayUnit == .meter)
    #expect(session.workspaceState.viewportGridSettings.visualSpacingMode == .fixed)
    #expect(session.workspaceState.revision == WorkspaceRevision(2))
    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationWorkspaceBatchDryRunReturnsProposalWithoutPublication() async throws {
    let session = EditorSession()
    let execution = try AutomationRunner().executeBatchTransaction(
        AutomationBatch(
            commands: [
                .setDisplayUnit(.meter),
                .setViewportGridSettings(
                    ViewportGridSettings(visualSpacingMode: .fixed)
                ),
            ]
        ),
        in: session,
        commits: false
    )

    #expect(execution.effect == .workspaceMutation)
    #expect(execution.proposedWorkspaceRevision == WorkspaceRevision(2))
    #expect(!execution.didCommit)
    #expect(execution.results.last?.workspaceRevision == WorkspaceRevision(2))
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.workspaceState.viewportGridSettings == .standard)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.generation == DocumentGeneration(0))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationWorkspaceBatchFailureRollsBackEveryCommand() async throws {
    let session = EditorSession()
    var caught: EditorError?

    do {
        _ = try AutomationRunner().executeBatch(
            AutomationBatch(
                commands: [
                    .setDisplayUnit(.meter),
                    .setActiveConstructionPlane(id: ConstructionPlaneSourceID()),
                ]
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .referenceUnresolved)
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.workspaceState.activeConstructionPlaneID == nil)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.generation == DocumentGeneration(0))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationBatchRejectsStaleWorkspaceRevision() async throws {
    let session = EditorSession()
    _ = try AutomationRunner().execute(.setDisplayUnit(.meter), in: session)
    var caught: EditorError?

    do {
        _ = try AutomationRunner().executeBatch(
            AutomationBatch(
                commands: [.setViewportGridSettings(.standard)],
                expectedGeneration: DocumentGeneration(0),
                expectedWorkspaceRevision: WorkspaceRevision(0)
            ),
            in: session
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .workspaceRevisionMismatch)
    #expect(session.workspaceState.revision == WorkspaceRevision(1))
    #expect(session.generation == DocumentGeneration(0))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationSourceBatchDryRunDoesNotPublishSource() async throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let execution = try AutomationRunner().executeBatchTransaction(
        AutomationBatch(
            commands: [
                .renameDocument(name: "Proposed"),
                .validateDocument,
            ]
        ),
        in: session,
        commits: false
    )

    #expect(execution.effect == .sourceMutation)
    #expect(execution.baseGeneration == DocumentGeneration(0))
    #expect(execution.proposedGeneration == DocumentGeneration(1))
    #expect(!execution.didCommit)
    #expect(execution.results.map(\.effect) == [.sourceMutation, .readOnly])
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func automationReadOnlyBatchDoesNotPublishEvaluationState() async throws {
    let session = EditorSession()
    let originalStore = session.store
    let execution = try AutomationRunner().executeBatchTransaction(
        AutomationBatch(commands: [.describeDocument, .validateDocument]),
        in: session,
        commits: true
    )

    #expect(execution.effect == .readOnly)
    #expect(!execution.didCommit)
    #expect(execution.baseGeneration == execution.proposedGeneration)
    #expect(execution.baseWorkspaceRevision == execution.proposedWorkspaceRevision)
    #expect(execution.results.allSatisfy { $0.effect == .readOnly })
    #expect(session.store === originalStore)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
}
