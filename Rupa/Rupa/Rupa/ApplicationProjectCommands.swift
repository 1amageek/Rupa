import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationProjectCommands: Commands {
    let coordinator: ApplicationProjectCoordinator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                coordinator.startNewProject()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!coordinator.canCreateNew)

            Button("Open Project…") {
                if let url = openProjectURL() {
                    coordinator.startLoad(from: url)
                }
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!coordinator.canOpen)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Project") {
                if let url = coordinator.currentFileURL ?? saveProjectURL() {
                    coordinator.startSave(to: url)
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!coordinator.canSave)

            Button("Save Project As…") {
                if let url = saveProjectURL() {
                    coordinator.startSave(to: url)
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!coordinator.canSave)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                coordinator.startUndo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!coordinator.canUndo)

            Button("Redo") {
                coordinator.startRedo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!coordinator.canRedo)
        }

        CommandGroup(after: .saveItem) {
            Button("Cancel Project Operation") {
                coordinator.cancelCurrentOperation()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!coordinator.canCancelOperation)
        }
    }

    private func openProjectURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [ApplicationProductConfiguration.projectContentType]
        panel.title = "Open Project"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func saveProjectURL() -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [ApplicationProductConfiguration.projectContentType]
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = coordinator.currentFileURL?.lastPathComponent
            ?? "Untitled.rupa"
        panel.title = "Save Project"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
