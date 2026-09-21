import Testing
@testable import RupaUI

@Test func workspaceHoverHintShowsTheHoveredControl() {
    var hint = WorkspaceHoverHint()

    hint.report("Grid Snap", from: "WorkspaceSnap.grid", isHovered: true)

    #expect(hint.text == "Grid Snap")
}

@Test func workspaceHoverHintClearsWhenItsOwnControlIsLeft() {
    var hint = WorkspaceHoverHint()
    hint.report("Grid Snap", from: "WorkspaceSnap.grid", isHovered: true)

    hint.report("Grid Snap", from: "WorkspaceSnap.grid", isHovered: false)

    #expect(hint.text == nil)
}

/// Hover events between neighbours arrive in no promised order: the next control's entry can
/// come before the last one's exit, and the late exit must not erase the newer hint.
@Test func workspaceHoverHintKeepsANewerNeighbourAgainstAStaleExit() {
    var hint = WorkspaceHoverHint()
    hint.report("Grid Snap", from: "WorkspaceSnap.grid", isHovered: true)

    hint.report("Object Targeting", from: "WorkspaceSnap.object", isHovered: true)
    hint.report("Grid Snap", from: "WorkspaceSnap.grid", isHovered: false)

    #expect(hint.text == "Object Targeting")
}

/// The guard keys on the control, not on the words, so two controls that describe themselves
/// the same way cannot clear each other.
@Test func workspaceHoverHintKeepsANeighbourThatSaysTheSameWords() {
    var hint = WorkspaceHoverHint()
    hint.report("Grid Snap", from: "WorkspaceSnap.grid", isHovered: true)

    hint.report("Grid Snap", from: "WorkspaceSnap.object", isHovered: true)
    hint.report("Grid Snap", from: "WorkspaceSnap.grid", isHovered: false)

    #expect(hint.text == "Grid Snap")
    #expect(hint.controlIdentifier == "WorkspaceSnap.object")
}
