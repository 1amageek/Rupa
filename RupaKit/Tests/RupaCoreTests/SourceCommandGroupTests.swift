import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func sourceCommandGroupEvaluatesAndRecordsHistoryOnce() throws {
    let session = EditorSession(document: .empty(named: "Before"))

    let names = try session.withSourceCommandGroup(named: "fixture.group") { stagedSession in
        _ = try stagedSession.execute(.renameDocument(name: "Intermediate"))
        _ = try stagedSession.execute(.renameDocument(name: "After"))
        return stagedSession.commandStack.undoEntries.map(\.commandName)
    }

    #expect(names.isEmpty)
    #expect(session.document.cadDocument.metadata.name == "After")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.store.completedEvaluationPassCount == 1)
    #expect(session.commandStack.undoEntries.count == 1)
    #expect(session.commandStack.undoEntries.first?.commandName == "fixture.group")

    _ = try session.undo()

    #expect(session.document.cadDocument.metadata.name == "Before")
}

@Test(.timeLimit(.minutes(1)))
func sourceCommandGroupFailureRestoresSourceHistoryAndEvaluation() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    let initialEvaluation = session.evaluationSnapshot

    #expect(throws: EditorError.self) {
        try session.withSourceCommandGroup(named: "fixture.failure") { stagedSession in
            _ = try stagedSession.execute(.renameDocument(name: "Never Published"))
            throw EditorError(code: .commandFailed, message: "Fixture failure.")
        } as Void
    }

    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.generation == DocumentGeneration())
    #expect(session.commandStack.undoEntries.isEmpty)
    #expect(session.commandStack.redoEntries.isEmpty)
    #expect(session.evaluationSnapshot == initialEvaluation)
    #expect(session.store.completedEvaluationPassCount == 0)
}

@Test(.timeLimit(.minutes(1)))
func sourceCommandGroupsRejectWorkspaceMutation() throws {
    let session = EditorSession(document: .empty(named: "Before"))

    #expect(throws: EditorError.self) {
        try session.withSourceCommandGroup(named: "fixture.invalid") { stagedSession in
            _ = try stagedSession.execute(.renameDocument(name: "Never Published"))
            _ = try stagedSession.execute(WorkspaceCommand.setDisplayUnit(.meter))
        }
    }

    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.workspaceState.displayUnit == .millimeter)
    #expect(session.generation == DocumentGeneration())
    #expect(session.workspaceState.revision == WorkspaceRevision())
}
