import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RupaCoreTypes
import RupaKit

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
            Menu("Import Geometry") {
                ForEach(ProjectGeometryFileFormat.allCases) { format in
                    Button("Import \(format.title)…") {
                        if let input = openGeometryURL(format: format) {
                            coordinator.startImportGeometry(from: input.url, format: format, unitForUnmarkedData: input.unit)
                        }
                    }
                }
            }
            .disabled(!coordinator.canSave)

            Menu("Export Geometry") {
                ForEach(ProjectGeometryFileFormat.allCases) { format in
                    Button(format == .step ? "Export CAD Source as STEP…" : "Export Visible Geometry as \(format.title)…") {
                        if let output = saveGeometryURL(format: format) {
                            coordinator.startExportGeometry(to: output.url, format: format, unit: output.unit)
                        }
                    }
                }
            }
            .disabled(!coordinator.canSave)

            Button("Cancel Project Operation") {
                coordinator.cancelCurrentOperation()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!coordinator.canCancelOperation)
        }
    }

    private func openGeometryURL(format: ProjectGeometryFileFormat) -> (url: URL, unit: LengthDisplayUnit?)? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        let extensions = format == .step ? ["step", "stp"] : [format.rawValue]
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.title = "Import \(format.title)"
        panel.message = format == .step
            ? "Append exact CAD bodies using the file's embedded units."
            : "Append editable Mesh geometry. Choose a unit if the file does not declare one. STL input must be binary."
        let units = NSPopUpButton()
        units.addItem(withTitle: "Use file units (required)")
        units.addItems(withTitles: LengthDisplayUnit.allCases.map { "\($0.rawValue) (\($0.symbol))" })
        units.setAccessibilityLabel("Unit for unmarked file coordinates")
        if format != .step {
            panel.accessoryView = NSStackView(views: [NSTextField(labelWithString: "Unit for unmarked data:"), units])
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let index = units.indexOfSelectedItem
        return (url, index > 0 ? LengthDisplayUnit.allCases[index - 1] : nil)
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

    private func saveGeometryURL(format: ProjectGeometryFileFormat) -> (url: URL, unit: LengthDisplayUnit)? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .data]
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(coordinator.snapshot?.projectName ?? "Untitled").\(format.rawValue)"
        panel.title = "Export \(format.title)"
        switch format {
        case .step:
            panel.message = "Exact CAD source only. Mesh, hidden bodies, placed or repeated occurrences require STL/OBJ. Save .rupa to retain the complete project."
        case .stl:
            panel.message = "Export visible surface geometry in world coordinates as binary STL. Materials, attributes and editing history are not part of STL."
        case .obj:
            panel.message = "Export visible geometry in world coordinates with supported normals and UVs. Unsupported materials or attributes produce an error."
        }
        let units = NSPopUpButton()
        units.addItems(withTitles: LengthDisplayUnit.allCases.map { "\($0.rawValue) (\($0.symbol))" })
        let current = coordinator.snapshot?.workspaceState.displayUnit ?? .millimeter
        if let index = LengthDisplayUnit.allCases.firstIndex(of: current) { units.selectItem(at: index) }
        units.setAccessibilityLabel("Export coordinate unit")
        panel.accessoryView = NSStackView(views: [NSTextField(labelWithString: "Output unit:"), units])
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (url, LengthDisplayUnit.allCases[units.indexOfSelectedItem])
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
