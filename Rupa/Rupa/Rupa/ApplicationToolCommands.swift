import SwiftUI
import RupaCore
import RupaUI

/// Presents the Tools menu from the focused workspace.
///
/// The menu owns no tool state. It reads the focused scene's
/// `WorkspaceToolCommands` for the selected tool and reaches activation through
/// exactly the closure the canvas palette button calls, so a tool cannot behave
/// differently depending on which surface started it. Names and keys come from
/// `ModelingTool`, so the menu never carries its own copy of either.
struct ApplicationToolCommands: Commands {
    @FocusedValue(\.workspaceToolCommands) private var toolCommands

    var body: some Commands {
        CommandMenu("Tools") {
            ForEach(ModelingTool.allCases) { tool in
                toolButton(tool)
            }
        }
    }

    /// One menu item per tool, checked while the focused workspace is in it.
    ///
    /// Entering a tool is the only direction the item drives: the workspace is
    /// always in exactly one tool, so unchecking the active item would ask for a
    /// state the workspace does not have.
    @ViewBuilder
    private func toolButton(_ tool: ModelingTool) -> some View {
        let item = Toggle(
            isOn: Binding(
                get: { toolCommands?.selectedTool == tool },
                set: { isOn in
                    guard isOn else {
                        return
                    }
                    toolCommands?.activate(tool)
                }
            )
        ) {
            Label(tool.title, systemImage: tool.systemImage)
        }
        // The command list is part of the window's chrome whether or not a
        // workspace is focused, so the menu is disabled rather than absent.
        .disabled(toolCommands == nil)

        if let key = tool.menuKeyEquivalent {
            item.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            item
        }
    }
}
