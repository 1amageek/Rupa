import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func isolatedReadTransactionDoesNotPublishEvaluationState() throws {
    let session = EditorSession()
    let originalStore = session.store
    let originalCommandStack = session.commandStack
    let originalEvaluationStatus = session.evaluationStatus

    let generation = try session.executeIsolatedReadTransaction { stagedSession in
        let result = try stagedSession.execute(.validateDocument)
        return result.generation
    }

    #expect(generation == DocumentGeneration(0))
    #expect(session.evaluationStatus == originalEvaluationStatus)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
    #expect(session.store === originalStore)
    #expect(session.commandStack === originalCommandStack)
}

@Test(.timeLimit(.minutes(1)))
func isolatedReadTransactionRejectsSourceMutation() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    var caught: EditorError?

    do {
        _ = try session.executeIsolatedReadTransaction { stagedSession in
            _ = try stagedSession.execute(.renameDocument(name: "Never Committed"))
        } as Void
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.generation == DocumentGeneration(0))
}

@Test(.timeLimit(.minutes(1)))
func isolatedReadTransactionRejectsWorkspaceMutation() throws {
    let session = EditorSession()
    var caught: EditorError?

    do {
        _ = try session.executeIsolatedReadTransaction { stagedSession in
            _ = try stagedSession.execute(WorkspaceCommand.setDisplayUnit(.meter))
        } as Void
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.workspaceState.revision == WorkspaceRevision(0))
}
