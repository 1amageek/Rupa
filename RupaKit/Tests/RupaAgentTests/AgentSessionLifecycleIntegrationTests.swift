import Foundation
import Testing
import RupaAgentIntegrationTestFixtures
import RupaAutomation
import RupaCore
@testable import RupaAgent

@Suite("Agent document lifecycle and history", .serialized)
struct AgentSessionLifecycleIntegrationTests {
    @Test func createSaveCloseAndOpenRoundTrip() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("Agent Created.rupa")
        let controller = AgentCommandController()

        let createResult = try requireSessionOperation(
            controller.handle(
                .createDocument(name: "Agent Created", outputPath: documentURL.path)
            ),
            operation: .create
        )
        let sessionID = createResult.session.id
        #expect(createResult.session.path == documentURL.standardizedFileURL.path)
        #expect(createResult.session.displayName == "Agent Created")
        #expect(!createResult.session.dirty)
        #expect(FileManager.default.fileExists(atPath: documentURL.path))

        var overwriteError: EditorError?
        do {
            try DocumentFileService().create(
                .empty(named: "Unexpected Overwrite"),
                at: documentURL
            )
        } catch let error as EditorError {
            overwriteError = error
        }
        #expect(overwriteError?.code == .documentSaveFailed)
        #expect(
            try DocumentFileService().load(from: documentURL)
                .cadDocument.metadata.name == "Agent Created"
        )

        guard case .command(let renameResult) = controller.handle(
            .execute(
                sessionID: sessionID,
                command: .renameDocument(name: "Persisted Rename"),
                expectedGeneration: DocumentGeneration(0)
            )
        ) else {
            Issue.record("Expected rename command result.")
            return
        }
        #expect(renameResult.generation == DocumentGeneration(1))

        guard case .save(let saveResult) = controller.handle(
            .save(
                sessionID: sessionID,
                expectedGeneration: DocumentGeneration(1)
            )
        ) else {
            Issue.record("Expected save result.")
            return
        }
        #expect(!saveResult.dirty)

        let closeResult = try requireSessionOperation(
            controller.handle(
                .closeDocument(
                    sessionID: sessionID,
                    expectedGeneration: DocumentGeneration(1),
                    discardUnsavedChanges: false
                )
            ),
            operation: .close
        )
        #expect(closeResult.session.displayName == "Persisted Rename")

        guard case .sessions(let closedSessions) = controller.handle(.sessions) else {
            Issue.record("Expected sessions response after close.")
            return
        }
        #expect(closedSessions.isEmpty)

        let openResult = try requireSessionOperation(
            controller.handle(.openDocument(path: documentURL.path)),
            operation: .open
        )
        #expect(openResult.session.id != sessionID)
        #expect(openResult.session.displayName == "Persisted Rename")
        #expect(openResult.session.generation == DocumentGeneration(0))
        #expect(!openResult.session.dirty)
    }

    @Test func closeRejectsDirtySessionUntilDiscardIsExplicit() throws {
        let controller = AgentCommandController()
        let createResult = try requireSessionOperation(
            controller.handle(.createDocument(name: "Dirty", outputPath: nil)),
            operation: .create
        )
        let sessionID = createResult.session.id
        guard case .command = controller.handle(
            .execute(
                sessionID: sessionID,
                command: .renameDocument(name: "Dirty Rename"),
                expectedGeneration: DocumentGeneration(0)
            )
        ) else {
            Issue.record("Expected rename command result.")
            return
        }

        let rejectedClose = controller.handle(
            .closeDocument(
                sessionID: sessionID,
                expectedGeneration: DocumentGeneration(1),
                discardUnsavedChanges: false
            )
        )
        guard case .failure(let closeError) = rejectedClose else {
            Issue.record("Expected dirty close failure.")
            return
        }
        #expect(closeError.code == .commandInvalid)

        guard case .sessions(let retainedSessions) = controller.handle(.sessions) else {
            Issue.record("Expected sessions response after rejected close.")
            return
        }
        #expect(retainedSessions.map(\.id) == [sessionID])

        _ = try requireSessionOperation(
            controller.handle(
                .closeDocument(
                    sessionID: sessionID,
                    expectedGeneration: DocumentGeneration(1),
                    discardUnsavedChanges: true
                )
            ),
            operation: .close
        )
    }

    @Test func openRejectsDocumentAlreadyRegisteredByPath() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            removeTemporaryDirectory(temporaryDirectory)
        }
        let documentURL = temporaryDirectory.appendingPathComponent("Duplicate.rupa")
        try DocumentFileService().save(.empty(named: "Duplicate"), to: documentURL)
        let controller = AgentCommandController()

        _ = try requireSessionOperation(
            controller.handle(.openDocument(path: documentURL.path)),
            operation: .open
        )
        guard case .failure(let error) = controller.handle(
            .openDocument(path: documentURL.path)
        ) else {
            Issue.record("Expected duplicate open failure.")
            return
        }
        #expect(error.code == .documentOpenInApp)
    }

    @Test func resetUndoAndRedoPreserveHistoryAndRejectStaleGeneration() throws {
        let controller = AgentCommandController()
        let session = EditorSession(document: .empty(named: "Before"))
        let sessionID = controller.register(session: session)
        _ = try session.execute(
            .renameDocument(name: "After"),
            expectedGeneration: DocumentGeneration(0)
        )

        guard case .failure(let missingGenerationError) = controller.handle(
            .undo(sessionID: sessionID, expectedGeneration: nil)
        ) else {
            Issue.record("Expected missing generation failure.")
            return
        }
        #expect(missingGenerationError.code == .commandInvalid)

        guard case .failure(let staleGenerationError) = controller.handle(
            .undo(sessionID: sessionID, expectedGeneration: DocumentGeneration(0))
        ) else {
            Issue.record("Expected stale generation failure.")
            return
        }
        #expect(staleGenerationError.code == .documentGenerationMismatch)
        #expect(session.document.cadDocument.metadata.name == "After")

        let undoResult = try requireSessionOperation(
            controller.handle(
                .undo(sessionID: sessionID, expectedGeneration: DocumentGeneration(1))
            ),
            operation: .undo
        )
        #expect(undoResult.commandName == "undo.renameDocument")
        #expect(undoResult.session.generation == DocumentGeneration(2))
        #expect(undoResult.canRedo)
        #expect(session.document.cadDocument.metadata.name == "Before")

        let redoResult = try requireSessionOperation(
            controller.handle(
                .redo(sessionID: sessionID, expectedGeneration: DocumentGeneration(2))
            ),
            operation: .redo
        )
        #expect(redoResult.commandName == "redo.renameDocument")
        #expect(redoResult.session.generation == DocumentGeneration(3))
        #expect(session.document.cadDocument.metadata.name == "After")

        let resetResult = try requireSessionOperation(
            controller.handle(
                .resetDocument(
                    sessionID: sessionID,
                    name: "Reset",
                    expectedGeneration: DocumentGeneration(3)
                )
            ),
            operation: .reset
        )
        #expect(resetResult.commandName == "resetDocument")
        #expect(resetResult.session.generation == DocumentGeneration(4))
        #expect(resetResult.canUndo)
        #expect(session.document.cadDocument.metadata.name == "Reset")
        #expect(session.document.cadDocument.designGraph.order.isEmpty)

        _ = try requireSessionOperation(
            controller.handle(
                .undo(sessionID: sessionID, expectedGeneration: DocumentGeneration(4))
            ),
            operation: .undo
        )
        #expect(session.document.cadDocument.metadata.name == "After")
        #expect(session.generation == DocumentGeneration(5))
    }

    private func requireSessionOperation(
        _ response: AgentResponse,
        operation: AgentSessionOperationResult.Operation
    ) throws -> AgentSessionOperationResult {
        guard case .sessionOperation(let result) = response else {
            Issue.record("Expected session operation result for \(operation.rawValue).")
            throw EditorError(
                code: .commandFailed,
                message: "Expected session operation result."
            )
        }
        #expect(result.operation == operation)
        return result
    }
}
