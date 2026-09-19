import RupaCore

/// What the eye and the lock in the selection strip do, and what they look like while they wait.
///
/// Both act on the whole selection, so neither can read its state off one member of it. A selection
/// holding a hidden node and a visible one has no single current value, and taking the last node's
/// and then toggling every node separately made "Hide Selection" put the hidden node back on
/// screen. One state, decided for the selection and applied to all of it, is what the label
/// promises and what a second click undoes.
struct WorkspaceSelectionDisplayAction: Equatable, Sendable {
    /// Anything still on screen is what the eye acts on, so a mixed selection hides.
    var hidesSelection: Bool
    /// Anything still editable is what the lock acts on, so a mixed selection locks.
    var locksSelection: Bool

    init(nodes: [SceneNode]) {
        hidesSelection = nodes.contains { $0.isVisible }
        locksSelection = nodes.contains { $0.isLocked == false }
    }

    /// The icon carries the state the selection is in; the help carries what clicking does to it.
    var visibilitySystemImage: String {
        hidesSelection ? "eye" : "eye.slash"
    }

    var visibilityHelp: String {
        hidesSelection ? "Hide Selection" : "Show Selection"
    }

    var lockSystemImage: String {
        locksSelection ? "lock.open" : "lock"
    }

    var lockHelp: String {
        locksSelection ? "Lock Selection" : "Unlock Selection"
    }
}
