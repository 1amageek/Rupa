import SwiftUI
import RupaUI

/// Adds the object copy actions to the Edit menu from the focused workspace.
///
/// The menu owns no selection. It reads the focused scene's `WorkspaceEditCommands` and calls the
/// same closures the workspace key and the Outliner call, so an action cannot behave differently
/// depending on where it was started.
struct ApplicationEditCommands: Commands {
    @FocusedValue(\.workspaceEditCommands) private var editCommands

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Duplicate") {
                editCommands?.duplicate?()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(editCommands?.duplicate == nil)
            Button("Mirror") {
                editCommands?.mirror?()
            }
            .keyboardShortcut("x", modifiers: .option)
            .disabled(editCommands?.mirror == nil)
            Button("Place") {
                editCommands?.place?()
            }
            .keyboardShortcut("d", modifiers: .control)
            .disabled(editCommands?.place == nil)
            Button("Copy with Placement") {
                editCommands?.copyWithPlacement?()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(editCommands?.copyWithPlacement == nil)
            Button("Paste with Placement") {
                editCommands?.pasteWithPlacement?()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(editCommands?.pasteWithPlacement == nil)
            Menu("Array") {
                Button("Rectangular Array") { editCommands?.rectangularArray?() }
                    .disabled(editCommands?.rectangularArray == nil)
                Button("Radial Array") { editCommands?.radialArray?() }
                    .disabled(editCommands?.radialArray == nil)
                Button("Curve Array") { editCommands?.curveArray?() }
                    .disabled(editCommands?.curveArray == nil)
            }
        }
    }
}
