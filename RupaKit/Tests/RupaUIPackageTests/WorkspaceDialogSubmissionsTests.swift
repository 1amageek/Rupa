import RupaCore
import Testing
@testable import RupaUI

/// A dialog command's OK makes one edit, and its completion ends only the dialog that submitted it.
@MainActor
@Suite struct WorkspaceDialogSubmissionsTests {
    private func deform() throws -> WorkspaceDeformSession {
        try #require(WorkspaceDeformSession(selectedCurves: [], selectedBodies: [SceneNodeID()]))
    }

    /// Keep Tools keeps Deform's dialog: a second OK before the first edit completed made a
    /// second edit.
    @Test func aSecondOKWhileTheFirstAppliesSubmitsNothing() throws {
        let submissions = WorkspaceDialogSubmissions()
        let dialog = try deform()
        #expect(submissions.begin(dialog.instance))
        #expect(submissions.isSubmitting(dialog.instance))
        #expect(!submissions.begin(dialog.instance))
        #expect(submissions.finish(dialog.instance, outcome: .applied, running: dialog.instance))
        #expect(!submissions.isSubmitting(dialog.instance))
    }

    /// A dialog cancelled and started again while the first edit applied is left alone.
    @Test func aCompletionEndsOnlyTheDialogThatSubmitted() throws {
        let submissions = WorkspaceDialogSubmissions()
        let first = try deform()
        let second = try deform()
        #expect(first.instance != second.instance)
        #expect(submissions.begin(first.instance))
        #expect(!submissions.finish(first.instance, outcome: .applied, running: second.instance))
        #expect(!submissions.finish(first.instance, outcome: .applied, running: nil))
        #expect(!submissions.isSubmitting(second.instance))
    }

    /// A refused edit leaves the dialog for another try; an edit that committed while its view
    /// failed exists, so it ends the dialog like an applied one.
    @Test func aRefusalKeepsTheDialogAndACommittedEditEndsIt() throws {
        let submissions = WorkspaceDialogSubmissions()
        let dialog = try deform()
        #expect(submissions.begin(dialog.instance))
        #expect(!submissions.finish(dialog.instance, outcome: .refused, running: dialog.instance))
        #expect(submissions.begin(dialog.instance))
        #expect(submissions.finish(dialog.instance, outcome: .appliedWithViewFailure, running: dialog.instance))
    }

    /// Editing a dialog keeps its instance: picks and options change the session, not which
    /// dialog it is.
    @Test func editingADialogKeepsItsInstance() throws {
        var dialog = try deform()
        let instance = dialog.instance
        dialog.pick(face: SelectionTarget(sceneNodeID: SceneNodeID(), component: .object))
        dialog.options.flipsNormal = true
        #expect(dialog.instance == instance)
    }
}
