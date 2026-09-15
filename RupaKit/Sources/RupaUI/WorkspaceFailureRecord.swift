import Foundation

/// One failure a workspace control refused a user operation on.
///
/// Order and repetition are part of the record: the same failure happening
/// twice is two entries, because a control that keeps failing is the signal.
/// See `RupaUI/DESIGN.md`, "Failure surfacing".
struct WorkspaceFailureRecord: Identifiable, Sendable {
    let id: UUID
    /// When the control refused, not when the log was read.
    let timestamp: Date
    /// The declaration that refused, captured from the call site.
    let operation: String
    /// The text the control shows, so the record and the surface agree.
    let message: String
    /// Reflected concrete error type, or `nil` for a refusal carrying no error.
    let errorType: String?
    /// Reflected error value. Typed errors in this repository describe
    /// themselves through `message` alone, so `localizedDescription` drops
    /// their `code`; this is where the dropped detail survives.
    let detail: String?

    init(
        operation: String,
        message: String,
        errorType: String? = nil,
        detail: String? = nil,
        timestamp: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operation = operation
        self.message = message
        self.errorType = errorType
        self.detail = detail
    }
}
