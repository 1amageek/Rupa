import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func preparedUndoPublishesOnlyAfterCommit() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    _ = try session.execute(
        .renameDocument(name: "After"),
        expectedTransactionRevision: DocumentTransactionRevision(0)
    )
    let publishedStore = session.store

    let prepared = try session.prepareUndo(
        expectedTransactionRevision: DocumentTransactionRevision(1)
    )

    #expect(session.store === publishedStore)
    #expect(session.document.cadDocument.metadata.name == "After")
    #expect(session.transactionRevision == DocumentTransactionRevision(1))
    #expect(prepared.stagedDocument.cadDocument.metadata.name == "Before")
    #expect(prepared.baseGeneration == DocumentGeneration(1))
    #expect(prepared.proposedGeneration == DocumentGeneration(2))
    #expect(prepared.baseTransactionRevision == DocumentTransactionRevision(1))
    #expect(prepared.proposedTransactionRevision == DocumentTransactionRevision(2))
    #expect(prepared.canUndo == false)
    #expect(prepared.canRedo)

    try session.commitPreparedHistoryTransaction(prepared)

    #expect(session.store !== publishedStore)
    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.transactionRevision == DocumentTransactionRevision(2))
    #expect(session.commandStack.canUndo == false)
    #expect(session.commandStack.canRedo)
}

@Test(.timeLimit(.minutes(1)))
func preparedRedoPublishesOnlyAfterCommit() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    _ = try session.execute(.renameDocument(name: "After"))
    _ = try session.undo()

    let prepared = try session.prepareRedo(
        expectedTransactionRevision: DocumentTransactionRevision(2)
    )

    #expect(session.document.cadDocument.metadata.name == "Before")
    #expect(prepared.stagedDocument.cadDocument.metadata.name == "After")
    #expect(prepared.canUndo)
    #expect(prepared.canRedo == false)

    try session.commitPreparedHistoryTransaction(prepared)

    #expect(session.document.cadDocument.metadata.name == "After")
    #expect(session.transactionRevision == DocumentTransactionRevision(3))
    #expect(session.commandStack.canUndo)
    #expect(session.commandStack.canRedo == false)
}

@Test(.timeLimit(.minutes(1)))
func preparedHistoryRejectsStalePublication() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    _ = try session.execute(.renameDocument(name: "Prepared Target"))
    let prepared = try session.prepareUndo(
        expectedTransactionRevision: DocumentTransactionRevision(1)
    )

    _ = try session.execute(
        .renameDocument(name: "Concurrent"),
        expectedTransactionRevision: DocumentTransactionRevision(1)
    )

    var error: EditorError?
    do {
        try session.commitPreparedHistoryTransaction(prepared)
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .documentTransactionRevisionMismatch)
    #expect(session.document.cadDocument.metadata.name == "Concurrent")
    #expect(session.transactionRevision == DocumentTransactionRevision(2))
    #expect(session.commandStack.undoEntries.count == 2)
}

@Test(.timeLimit(.minutes(1)))
func preparedHistoryRejectsCleanMarkerChanges() throws {
    let session = EditorSession(document: .empty(named: "Before"))
    _ = try session.execute(.renameDocument(name: "After"))
    let prepared = try session.prepareUndo(
        expectedTransactionRevision: DocumentTransactionRevision(1)
    )

    session.markClean()

    var error: EditorError?
    do {
        try session.commitPreparedHistoryTransaction(prepared)
    } catch let caught as EditorError {
        error = caught
    }

    #expect(error?.code == .commandInvalid)
    #expect(session.document.cadDocument.metadata.name == "After")
    #expect(session.isDirty == false)
    #expect(session.transactionRevision == DocumentTransactionRevision(1))
    #expect(session.commandStack.canUndo)
}

@Test(.timeLimit(.minutes(1)))
func preparingEmptyHistoryDoesNotMutateSession() throws {
    let session = EditorSession(document: .empty(named: "Retained"))
    let publishedStore = session.store

    #expect(throws: EditorError.self) {
        _ = try session.prepareUndo(
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    }

    #expect(session.store === publishedStore)
    #expect(session.document.cadDocument.metadata.name == "Retained")
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.transactionRevision == DocumentTransactionRevision(0))
}
