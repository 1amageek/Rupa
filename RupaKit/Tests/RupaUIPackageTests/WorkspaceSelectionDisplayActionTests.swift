import RupaCore
import Testing
@testable import RupaUI

/// The everyday case: one thing picked, and the button says what happens to it.
@Test func workspaceSelectionDisplayActionFollowsASingleNode() {
    let shown = WorkspaceSelectionDisplayAction(nodes: [node(isVisible: true, isLocked: false)])
    let hidden = WorkspaceSelectionDisplayAction(nodes: [node(isVisible: false, isLocked: true)])
    #expect(shown.hidesSelection)
    #expect(shown.visibilityHelp == "Hide Selection")
    #expect(shown.visibilitySystemImage == "eye")
    #expect(shown.locksSelection)
    #expect(shown.lockHelp == "Lock Selection")
    #expect(shown.lockSystemImage == "lock.open")
    #expect(hidden.hidesSelection == false)
    #expect(hidden.visibilityHelp == "Show Selection")
    #expect(hidden.visibilitySystemImage == "eye.slash")
    #expect(hidden.locksSelection == false)
    #expect(hidden.lockHelp == "Unlock Selection")
    #expect(hidden.lockSystemImage == "lock")
}

/// The case the old buttons got wrong: pick one hidden node and one visible one, and "Hide
/// Selection" toggled each in turn, so it put the hidden node back on screen. Whatever the mix, the
/// button now names one state and gives it to everything.
@Test func workspaceSelectionDisplayActionActsOnAMixedSelectionAsOne() {
    let mixed = WorkspaceSelectionDisplayAction(nodes: [
        node(isVisible: true, isLocked: true),
        node(isVisible: false, isLocked: false),
    ])
    #expect(mixed.hidesSelection)
    #expect(mixed.visibilityHelp == "Hide Selection")
    #expect(mixed.locksSelection)
    #expect(mixed.lockHelp == "Lock Selection")
}

/// Hiding everything leaves a selection that shows everything, so a second click undoes the first.
@Test func workspaceSelectionDisplayActionReversesItself() {
    let mixed = [
        node(isVisible: true, isLocked: true),
        node(isVisible: false, isLocked: false),
    ]
    let first = WorkspaceSelectionDisplayAction(nodes: mixed)
    let applied = mixed.map {
        node(isVisible: first.hidesSelection == false, isLocked: first.locksSelection, from: $0)
    }
    let second = WorkspaceSelectionDisplayAction(nodes: applied)
    let isEveryNodeHidden = applied.filter(\.isVisible).isEmpty
    let isEveryNodeLocked = applied.filter { $0.isLocked == false }.isEmpty
    #expect(isEveryNodeHidden)
    #expect(isEveryNodeLocked)
    #expect(second.hidesSelection == false)
    #expect(second.locksSelection == false)
}

private func node(isVisible: Bool, isLocked: Bool) -> SceneNode {
    SceneNode(name: "Node", isVisible: isVisible, isLocked: isLocked)
}

private func node(isVisible: Bool, isLocked: Bool, from source: SceneNode) -> SceneNode {
    var updated = source
    updated.isVisible = isVisible
    updated.isLocked = isLocked
    return updated
}
