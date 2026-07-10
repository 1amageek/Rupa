import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func isolatedWorkspaceTransactionPublishesOnlyWorkspaceState() throws {
    let session = EditorSession(document: .empty(named: "Source"))
    let originalStore = session.store
    let originalCommandStack = session.commandStack
    let originalDocument = session.document

    let execution = try session.executeIsolatedWorkspaceTransaction(
        commits: true
    ) { stagedSession in
        _ = try stagedSession.execute(WorkspaceCommand.setDisplayUnit(.meter))
        _ = try stagedSession.execute(
            WorkspaceCommand.setViewportGridSettings(
                ViewportGridSettings(visualSpacingMode: .fixed)
            )
        )
        return stagedSession.workspaceState.displayUnit
    }

    #expect(execution.value == .meter)
    #expect(execution.baseRevision == WorkspaceRevision(0))
    #expect(execution.proposedRevision == WorkspaceRevision(2))
    #expect(execution.didCommit)
    #expect(session.workspaceState.displayUnit == .meter)
    #expect(session.workspaceState.viewportGridSettings.visualSpacingMode == .fixed)
    #expect(session.workspaceState.revision == WorkspaceRevision(2))
    #expect(session.generation == DocumentGeneration(0))
    #expect(!session.isDirty)
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.document.cadDocument.metadata.name == originalDocument.cadDocument.metadata.name)
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@Test(.timeLimit(.minutes(1)))
func isolatedWorkspaceTransactionDryRunDoesNotPublishState() throws {
    let session = EditorSession()
    let originalStore = session.store
    let originalCommandStack = session.commandStack

    let execution = try session.executeIsolatedWorkspaceTransaction(
        commits: false
    ) { stagedSession in
        _ = try stagedSession.execute(WorkspaceCommand.setDisplayUnit(.meter))
        return stagedSession.workspaceState.displayUnit
    }

    #expect(execution.value == .meter)
    #expect(execution.baseRevision == WorkspaceRevision(0))
    #expect(execution.proposedRevision == WorkspaceRevision(1))
    #expect(!execution.didCommit)
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@Test(.timeLimit(.minutes(1)))
func isolatedWorkspaceTransactionRejectsSourceMutation() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    var caught: EditorError?

    do {
        _ = try session.executeIsolatedWorkspaceTransaction(
            commits: true
        ) { stagedSession in
            _ = try stagedSession.execute(WorkspaceCommand.setDisplayUnit(.meter))
            _ = try stagedSession.execute(.renameDocument(name: "Never Committed"))
        } as IsolatedWorkspaceTransactionExecution<Void>
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func workspaceRevisionRequirementRejectsStaleRevision() throws {
    var workspaceState = WorkspaceState()
    _ = try workspaceState.apply(
        .setDisplayUnit(.meter),
        document: .empty()
    )

    var caught: EditorError?
    do {
        try workspaceState.requireRevision(WorkspaceRevision(0))
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .workspaceRevisionMismatch)
    #expect(caught?.message.contains("current revision is 1") == true)
}
