import Foundation
import Observation
import RupaKit
import RupaProject

/// What a UI operation reports when its mutation committed but its view could not be built.
///
/// The mutation is never replayed: the document and Undo already hold it. A caller that ends a
/// command on success ends it here too, because the command's edit exists.
enum WorkspaceCommittedOperationError: Error, LocalizedError, Sendable {
    /// The committed view was rebuilt; the workspace shows the edit and editing continues.
    case recovered(message: String)
    /// The committed view could not be rebuilt; the workspace refuses edits from here on.
    case unrecovered(message: String, recoveryFailure: String)
    /// An operation refused because an earlier committed view could not be rebuilt.
    case workspaceUnavailable(reason: String)

    var errorDescription: String? {
        switch self {
        case .recovered(let message):
            "The edit was applied, and its view was rebuilt after a presentation failure: \(message)"
        case .unrecovered(let message, let recoveryFailure):
            "The edit was applied, but its view could not be rebuilt (\(recoveryFailure)); "
                + "editing is unavailable until the project is reopened. \(message)"
        case .workspaceUnavailable(let reason):
            "Editing is unavailable until the project is reopened: \(reason)"
        }
    }
}

/// The UI's one owner of a mutation that committed but whose view failed
/// (`ProjectWorkspacePostCommitError`).
///
/// Every UI operation runs through `run(_:)` inside its operation-queue slot, so the committed
/// view is rebuilt (`recoverCommittedView`, the same contract the application's save and history
/// paths keep) before the next queued operation plans against it. When the view cannot be rebuilt
/// the workspace no longer shows its own document: `unavailableReason` is set, and every later
/// operation is refused by `checkAvailable()` instead of planning against a stale view.
@MainActor
@Observable
final class WorkspaceCommittedOperationRecovery {
    typealias Recover = @MainActor (ProjectStateSnapshot) async throws -> Void

    @ObservationIgnored private let recover: Recover
    /// Why editing stopped, once a committed view could not be rebuilt.
    private(set) var unavailableReason: String?

    init(recover: @escaping Recover) {
        self.recover = recover
    }

    convenience init(workspace: ProjectWorkspace) {
        self.init { state in
            _ = try await workspace.recoverCommittedView(state)
        }
    }

    /// Refuses an operation once a committed view could not be rebuilt.
    func checkAvailable() throws {
        if let unavailableReason {
            throw WorkspaceCommittedOperationError.workspaceUnavailable(reason: unavailableReason)
        }
    }

    /// Runs `operation`; a committed mutation whose view failed is recovered here and reported as
    /// `WorkspaceCommittedOperationError`, never replayed.
    func run<Result: Sendable>(
        _ operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        try checkAvailable()
        do {
            return try await operation()
        } catch let error as ProjectWorkspacePostCommitError {
            do {
                try await recover(error.commit.state)
            } catch let recoveryError {
                let reason = "\(error.message) The view could not be rebuilt: \(recoveryError.localizedDescription)"
                unavailableReason = reason
                throw WorkspaceCommittedOperationError.unrecovered(
                    message: error.message,
                    recoveryFailure: recoveryError.localizedDescription
                )
            }
            throw WorkspaceCommittedOperationError.recovered(message: error.message)
        }
    }
}
