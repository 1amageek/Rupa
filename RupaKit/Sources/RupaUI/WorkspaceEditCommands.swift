import SwiftUI

/// The focused workspace's object edit actions, published for the Edit menu.
///
/// The menu is presented by the App while the selection lives in the workspace view, so the two
/// are joined by one focused scene value. Each action is the same closure the workspace key and the
/// Outliner call, and is `nil` when the current selection cannot take it, so the menu disables the
/// item instead of offering an action Core would refuse.
public struct WorkspaceEditCommands {
    /// Copies the selected objects in place and selects the copies for moving.
    public var duplicate: (@MainActor () -> Void)?
    /// Arrays the selected objects along the parent's X axis.
    public var rectangularArray: (@MainActor () -> Void)?
    /// Arrays the selected objects around a center the user picks next.
    public var radialArray: (@MainActor () -> Void)?
    /// Arrays the selected objects along a path curve the user picks next.
    public var curveArray: (@MainActor () -> Void)?

    public init(
        duplicate: (@MainActor () -> Void)?,
        rectangularArray: (@MainActor () -> Void)? = nil,
        radialArray: (@MainActor () -> Void)? = nil,
        curveArray: (@MainActor () -> Void)? = nil
    ) {
        self.duplicate = duplicate
        self.rectangularArray = rectangularArray
        self.radialArray = radialArray
        self.curveArray = curveArray
    }
}

private struct WorkspaceEditCommandsKey: FocusedValueKey {
    typealias Value = WorkspaceEditCommands
}

extension FocusedValues {
    /// The edit commands of the focused workspace, or `nil` when no workspace is focused.
    public var workspaceEditCommands: WorkspaceEditCommands? {
        get { self[WorkspaceEditCommandsKey.self] }
        set { self[WorkspaceEditCommandsKey.self] = newValue }
    }
}
