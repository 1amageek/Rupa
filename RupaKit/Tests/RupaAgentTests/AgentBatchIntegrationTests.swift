import Foundation
import Testing
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@Test func agentBatchFailureRollsBackDocumentAndUndoHistory() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: .empty(named: "Before Batch"))
    _ = try AutomationRunner().execute(
        .createExtrudedRectangle(
            name: "Stable Body",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(12.0, .millimeter),
            depth: .length(6.0, .millimeter),
            direction: .normal
        ),
        in: session
    )
    let baselineGeneration = session.generation
    let baselineUndoCount = session.commandStack.undoEntries.count
    let baselineEvaluation = try #require(session.currentEvaluation)
    session.markClean()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .executeBatch(
            sessionID: sessionID,
            batch: AutomationBatch(
                commands: [
                    .renameDocument(name: "Partially Applied"),
                    .deleteParameter(name: "missing"),
                ],
                expectedGeneration: baselineGeneration
            )
        )
    )

    guard case .failure(let error) = response else {
        Issue.record("Expected batch failure.")
        return
    }
    #expect(error.code == .referenceUnresolved)
    #expect(session.document.cadDocument.metadata.name == "Before Batch")
    #expect(session.generation == baselineGeneration)
    #expect(!session.isDirty)
    #expect(session.commandStack.undoEntries.count == baselineUndoCount)
    #expect(!session.commandStack.canRedo)
    let restoredEvaluation = try #require(session.currentEvaluation)
    #expect(try restoredEvaluation.matches(
        document: session.document,
        generation: baselineGeneration
    ))
    #expect(restoredEvaluation.evaluatedDocument.meshes.count == baselineEvaluation.evaluatedDocument.meshes.count)
}

@Test func agentBatchSuccessReturnsFinalGenerationAndDirtyState() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: .empty(named: "Before Batch"))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .executeBatch(
            sessionID: sessionID,
            batch: AutomationBatch(
                commands: [
                    .renameDocument(name: "Intermediate Batch"),
                    .renameDocument(name: "After Batch"),
                ],
                expectedGeneration: DocumentGeneration(0)
            )
        )
    )

    guard case .batch(let result) = response else {
        Issue.record("Expected batch result.")
        return
    }
    #expect(result.commandCount == 2)
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(result.dirty)
    #expect(session.document.cadDocument.metadata.name == "After Batch")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.undoEntries.count == 1)

    _ = try session.undo()

    #expect(session.document.cadDocument.metadata.name == "Before Batch")
}
