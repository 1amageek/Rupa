import Foundation
import RupaAutomation

/// A result-projection failure observed after an EditorSession mutation committed.
///
/// Callers must not retry the request. `finalContext` is the exact committed
/// session state from which presentation or a later read can be rebuilt.
public struct DomainCommandPostCommitError: Error, LocalizedError, Sendable {
    public let record: DomainCommandExecutionRecord
    public let finalContext: AutomationBatchFinalContext
    public let message: String

    public init(
        record: DomainCommandExecutionRecord,
        finalContext: AutomationBatchFinalContext,
        message: String
    ) {
        self.record = record
        self.finalContext = finalContext
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
