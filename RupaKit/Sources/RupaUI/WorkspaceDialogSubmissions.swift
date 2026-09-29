import Foundation
import Observation

/// One running dialog command: minted when the dialog starts, kept by every copy of its session,
/// and new when the command starts again.
struct WorkspaceDialogInstance: Hashable, Sendable {
    private let id = UUID()
}

/// The one owner of a dialog command's submission: a dialog command (Fillet, Cut Curve, Boolean,
/// Cut, Deform, Bridge Edge, Project, Rebuild) moves from editing to submitting when OK is pressed
/// and ends when its edit completes.
///
/// While an instance is submitting, OK again is refused, so one press makes one edit (Keep Tools
/// keeps Deform's dialog, and a second OK before the first edit completed made a second edit).
/// A completion ends the dialog only when the instance that submitted is still the running one,
/// so a dialog cancelled and started again while the first edit applied is left alone.
@MainActor
@Observable
final class WorkspaceDialogSubmissions {
    /// How a submitted edit ended.
    enum Outcome: Equatable, Sendable {
        /// The edit changed the document.
        case applied
        /// The edit committed, but its view had to be rebuilt or could not be
        /// (`WorkspaceCommittedOperationError`): the edit exists all the same.
        case appliedWithViewFailure
        /// Core refused the edit, or it changed nothing: the dialog stays for another try.
        case refused
    }

    private(set) var submitting: Set<WorkspaceDialogInstance> = []

    /// Whether `instance` is submitting, so its OK stays disabled.
    func isSubmitting(_ instance: WorkspaceDialogInstance?) -> Bool {
        instance.map(submitting.contains) ?? false
    }

    /// Moves `instance` to submitting; false when it already is, and nothing may be submitted.
    func begin(_ instance: WorkspaceDialogInstance) -> Bool {
        submitting.insert(instance).inserted
    }

    /// Ends `instance`'s submission; true when the completion ends the dialog: the edit exists and
    /// `running`, the dialog now open for the command, is the one that submitted it.
    func finish(
        _ instance: WorkspaceDialogInstance,
        outcome: Outcome,
        running: WorkspaceDialogInstance?
    ) -> Bool {
        submitting.remove(instance)
        return outcome != .refused && running == instance
    }
}
