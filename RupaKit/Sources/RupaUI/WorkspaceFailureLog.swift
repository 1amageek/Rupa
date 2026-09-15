import Foundation
import Observation
import OSLog

/// Ordered, bounded, non-deduplicating record of every failure a workspace
/// control refuses a user operation on.
///
/// The red inline labels, the Outliner alert, and `modelingPreview.errorMessage`
/// are transient views of the newest failure for one control and are cleared by
/// the next run, a Cancel, or a selection change. This log is the authority for
/// what failed; a surface is the authority only for what is visible right now.
/// See `RupaUI/DESIGN.md`, "Failure surfacing".
@MainActor
@Observable
final class WorkspaceFailureLog {
    /// The workspace chrome is a single window scene, so one log serves it.
    static let shared = WorkspaceFailureLog()

    /// Oldest first. Never deduplicated, unlike `EditorDiagnostic.stableMerged`.
    private(set) var records: [WorkspaceFailureRecord] = []

    /// Retained-entry ceiling. Oldest entries are dropped first.
    let limit: Int

    @ObservationIgnored
    private let logger = Logger(
        subsystem: "RupaUI",
        category: "WorkspaceFailureLog"
    )

    init(limit: Int = 200) {
        self.limit = limit
    }

    /// Records `error` and returns the message the calling control displays, so
    /// a catch reads `surface = record(error)` and shows the recorded text.
    @discardableResult
    func record(_ error: any Error, operation: String = #function) -> String {
        let message = error.localizedDescription
        append(
            WorkspaceFailureRecord(
                operation: operation,
                message: message,
                errorType: String(reflecting: type(of: error)),
                detail: String(reflecting: error)
            )
        )
        return message
    }

    /// Records a refusal that carries no `Error` value, where a guard discards a
    /// user gesture. `message` names the precondition that was not met.
    func record(refusal message: String, operation: String = #function) {
        append(WorkspaceFailureRecord(operation: operation, message: message))
    }

    func clear() {
        records.removeAll()
    }

    private func append(_ record: WorkspaceFailureRecord) {
        records.append(record)
        if records.count > limit {
            records.removeFirst(records.count - limit)
        }
        logger.error(
            """
            \(record.operation, privacy: .public): \
            \(record.message, privacy: .public) \
            [\(record.errorType ?? "refusal", privacy: .public)] \
            \(record.detail ?? "", privacy: .public)
            """
        )
    }
}
