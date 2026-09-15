import Foundation
import Testing
import RupaCoreTypes
@testable import RupaUI

/// Records through the same entry point a control's `catch` uses, so the
/// captured `operation` is this function rather than the log's own frame.
@MainActor
private func recordThroughACallSite(
    _ error: any Error,
    into log: WorkspaceFailureLog
) -> String {
    log.record(error)
}

@MainActor
@Test func workspaceFailureLogReturnsTheMessageTheControlDisplays() {
    let log = WorkspaceFailureLog()
    let error = EditorError(code: .commandInvalid, message: "Pick two bodies.")

    let displayed = log.record(error)

    #expect(displayed == "Pick two bodies.")
    #expect(log.records.count == 1)
    #expect(log.records[0].message == "Pick two bodies.")
}

@MainActor
@Test func workspaceFailureLogKeepsTheDetailLocalizedDescriptionDrops() {
    let log = WorkspaceFailureLog()
    let error = EditorError(code: .commandInvalid, message: "Pick two bodies.")

    log.record(error)

    // `EditorError` describes itself through `message` alone, so the code is
    // absent from what the red label shows and must survive in the record.
    #expect(error.localizedDescription.contains("commandInvalid") == false)
    let record = log.records[0]
    #expect(record.detail?.contains("commandInvalid") == true)
    #expect(record.errorType?.contains("EditorError") == true)
}

@MainActor
@Test func workspaceFailureLogNamesTheDeclarationThatRefused() {
    let log = WorkspaceFailureLog()
    let error = EditorError(code: .commandInvalid, message: "Pick two bodies.")

    _ = recordThroughACallSite(error, into: log)

    #expect(log.records[0].operation == "recordThroughACallSite(_:into:)")
}

@MainActor
@Test func workspaceFailureLogNeverDeduplicatesARepeatedFailure() {
    let log = WorkspaceFailureLog()
    let error = EditorError(code: .commandInvalid, message: "Pick two bodies.")

    log.record(error)
    log.record(error)

    // A control that keeps failing is the signal, so the second run is a
    // second entry, unlike `EditorDiagnostic.stableMerged`.
    #expect(log.records.count == 2)
}

@MainActor
@Test func workspaceFailureLogDropsTheOldestEntryPastItsLimit() {
    let log = WorkspaceFailureLog(limit: 2)

    log.record(refusal: "first", operation: "a()")
    log.record(refusal: "second", operation: "b()")
    log.record(refusal: "third", operation: "c()")

    #expect(log.records.count == 2)
    #expect(log.records.map(\.message) == ["second", "third"])
}

@MainActor
@Test func workspaceFailureLogRecordsAGuardRefusalWithoutAnErrorValue() {
    let log = WorkspaceFailureLog()

    log.record(refusal: "Choose a construction plane.", operation: "measure()")

    let record = log.records[0]
    #expect(record.message == "Choose a construction plane.")
    #expect(record.operation == "measure()")
    #expect(record.errorType == nil)
    #expect(record.detail == nil)
}

@MainActor
@Test func workspaceFailureLogClearsEveryRetainedEntry() {
    let log = WorkspaceFailureLog()
    log.record(refusal: "first", operation: "a()")
    log.record(refusal: "second", operation: "b()")

    log.clear()

    #expect(log.records.isEmpty)
}
