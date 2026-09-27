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
            Button("Complete Edge") {
                editCommands?.completeEdge?()
            }
            .disabled(editCommands?.completeEdge == nil)
            Button("Subdivide") {
                editCommands?.subdivide?()
            }
            .disabled(editCommands?.subdivide == nil)
            Button("Split Segment") {
                editCommands?.splitSegment?()
            }
            .disabled(editCommands?.splitSegment == nil)
            Button("Insert Knot") {
                editCommands?.insertKnot?()
            }
            .disabled(editCommands?.insertKnot == nil)
            Button("Bridge") {
                editCommands?.bridge?()
            }
            .disabled(editCommands?.bridge == nil)
            Button("Reverse Curve") {
                editCommands?.reverseCurves?()
            }
            .disabled(editCommands?.reverseCurves == nil)
            Button("Create Instance") {
                editCommands?.createInstance?()
            }
            .disabled(editCommands?.createInstance == nil)
            Button("Realize Instances") {
                editCommands?.realizeInstances?()
            }
            .disabled(editCommands?.realizeInstances == nil)
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
