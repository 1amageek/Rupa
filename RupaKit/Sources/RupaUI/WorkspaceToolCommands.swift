import RupaCore
import SwiftUI

/// The focused workspace's tool selection, published for the menu bar.
///
/// The Tools menu is presented by the App and the active tool lives in the
/// workspace view, so the two are joined by one focused scene value rather than
/// by moving tool state out of the view. The menu owns no tool state of its own
/// and reaches activation through exactly the closure the palette button calls,
/// so a tool cannot behave differently depending on which surface started it.
public struct WorkspaceToolCommands {
    /// The tool the focused workspace is currently in.
    public var selectedTool: ModelingTool

    /// Enters a tool, with the same effect as picking it from the palette.
    public var activate: @MainActor (ModelingTool) -> Void

    public init(
        selectedTool: ModelingTool,
        activate: @escaping @MainActor (ModelingTool) -> Void
    ) {
        self.selectedTool = selectedTool
        self.activate = activate
    }
}

private struct WorkspaceToolCommandsKey: FocusedValueKey {
    typealias Value = WorkspaceToolCommands
}

extension FocusedValues {
    /// The tool commands of the focused workspace, or `nil` when no workspace
    /// is focused and the Tools menu therefore has nothing to act on.
    public var workspaceToolCommands: WorkspaceToolCommands? {
        get { self[WorkspaceToolCommandsKey.self] }
        set { self[WorkspaceToolCommandsKey.self] = newValue }
    }
}
