import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func isolatedTransactionCommitsMultipleMutationsAsOneUndoEntry() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let originalStore = session.store
    let originalCommandStack = session.commandStack

    let execution = try session.executeIsolatedSourceTransaction(
        commandName: "fixture.atomic",
        commits: true
    ) { stagedSession in
        _ = try stagedSession.execute(.renameDocument(name: "Intermediate"))
        _ = try stagedSession.execute(.renameDocument(name: "After"))
        return stagedSession.document.cadDocument.metadata.name
    }

    #expect(execution.value == "After")
    #expect(execution.baseGeneration == DocumentGeneration(0))
    #expect(execution.proposedGeneration == DocumentGeneration(2))
    #expect(execution.didCommit)
    #expect(session.commandStack.undoEntries.count == 1)
    #expect(session.commandStack.undoEntries.first?.commandName == "fixture.atomic")
    #expect(session.document.cadDocument.metadata.name == "After")
    #expect(session.store !== originalStore)
    #expect(session.commandStack === originalCommandStack)
    #expect(originalStore.document.cadDocument.metadata.name == "Before")
    #expect(originalStore.generation == DocumentGeneration(0))
    #expect(originalCommandStack.undoEntries.count == 1)

    _ = try session.undo()

    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.workspaceState.displayUnit == .millimeter)
}

@Test(.timeLimit(.minutes(1)))
func isolatedTransactionDryRunDoesNotPublishStagedState() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let originalStore = session.store
    let originalCommandStack = session.commandStack
    let initialDiagnostics = session.diagnostics
    let initialEvaluationStatus = session.evaluationStatus

    let execution = try session.executeIsolatedSourceTransaction(
        commandName: "fixture.dry-run",
        commits: false
    ) { stagedSession in
        _ = try stagedSession.execute(.renameDocument(name: "Proposed"))
        return stagedSession.document.cadDocument.metadata.name
    }

    #expect(execution.value == "Proposed")
    #expect(execution.proposedGeneration == DocumentGeneration(1))
    #expect(!execution.didCommit)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.diagnostics == initialDiagnostics)
    #expect(session.evaluationStatus == initialEvaluationStatus)
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@Test(.timeLimit(.minutes(1)))
func isolatedTransactionFailureLeavesDocumentAndHistoryUnchanged() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let originalStore = session.store
    let originalCommandStack = session.commandStack
    var caught: EditorError?

    do {
        _ = try session.executeIsolatedSourceTransaction(
            commandName: "fixture.failure",
            commits: true
        ) { stagedSession in
            _ = try stagedSession.execute(.renameDocument(name: "Never Committed"))
            throw EditorError(code: .commandFailed, message: "Fixture failure.")
        } as IsolatedSourceTransactionExecution<Void>
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandFailed)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.commandStack.redoEntries.isEmpty)
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@Test(.timeLimit(.minutes(1)))
func isolatedSourceTransactionRejectsWorkspaceMutation() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let initialWorkspaceRevision = session.workspaceState.revision
    var caught: EditorError?

    do {
        _ = try session.executeIsolatedSourceTransaction(
            commandName: "fixture.invalid-effect",
            commits: true
        ) { stagedSession in
            _ = try stagedSession.execute(.renameDocument(name: "Never Committed"))
            _ = try stagedSession.execute(WorkspaceCommand.setDisplayUnit(.meter))
        } as IsolatedSourceTransactionExecution<Void>
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.workspaceState.revision == initialWorkspaceRevision)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.undoEntries.isEmpty)
}
