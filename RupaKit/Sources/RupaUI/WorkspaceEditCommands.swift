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
    /// Starts Mirror on the selected objects.
    public var mirror: (@MainActor () -> Void)?
    /// Places copies or instances of the selected objects from one picked point onto others.
    public var place: (@MainActor () -> Void)?
    /// Copies the selected objects with a reference point picked next, for Paste with Placement.
    public var copyWithPlacement: (@MainActor () -> Void)?
    /// Places the objects on the pasteboard at destinations picked next.
    public var pasteWithPlacement: (@MainActor () -> Void)?
    /// Arrays the selected objects along the parent's X axis.
    public var rectangularArray: (@MainActor () -> Void)?
    /// Arrays the selected objects around a center the user picks next.
    public var radialArray: (@MainActor () -> Void)?
    /// Arrays the selected objects along a path curve the user picks next.
    public var curveArray: (@MainActor () -> Void)?

    public init(
        duplicate: (@MainActor () -> Void)?,
        mirror: (@MainActor () -> Void)? = nil,
        place: (@MainActor () -> Void)? = nil,
        copyWithPlacement: (@MainActor () -> Void)? = nil,
        pasteWithPlacement: (@MainActor () -> Void)? = nil,
        rectangularArray: (@MainActor () -> Void)? = nil,
        radialArray: (@MainActor () -> Void)? = nil,
        curveArray: (@MainActor () -> Void)? = nil
    ) {
        self.duplicate = duplicate
        self.mirror = mirror
        self.place = place
        self.copyWithPlacement = copyWithPlacement
        self.pasteWithPlacement = pasteWithPlacement
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
