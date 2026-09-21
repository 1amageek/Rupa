import RupaCore
import RupaRendering
import SwiftUI

struct WorkspaceToolPalette: View {
    var selectedTool: ModelingTool
    var solidShape: WorkspaceSolidShape
    var selectedOperation: ModelingOperationDraft.Kind?
    var activate: (ModelingTool) -> Void
    var activateSolid: (WorkspaceSolidShape) -> Void
    var beginModelingOperation: (ModelingOperationDraft.Kind) -> Void
    var accessibilityIdentifier: (ModelingTool) -> String
    @State private var isSolidPickerPresented = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: WorkspaceToolPaletteMetrics.itemSpacing) {
                ForEach(ModelingTool.allCases) { tool in
                    if tool == .solid {
                        toolPaletteButton(tool)
                            .popover(isPresented: $isSolidPickerPresented, arrowEdge: .trailing) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(WorkspaceSolidShape.allCases) { shape in
                                        Button(shape.rawValue, systemImage: shape.systemImage) {
                                            isSolidPickerPresented = false
                                            activateSolid(shape)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(12)
                            }
                    } else {
                        toolPaletteButton(tool)
                    }
                }
                Divider().padding(.horizontal, 6)
                ForEach(ModelingOperationDraft.Kind.paletteOperations) { kind in
                    paletteButton(
                        title: kind.rawValue,
                        hint: kind.rawValue,
                        symbol: kind.systemImage,
                        isSelected: selectedOperation == kind,
                        identifier: "CanvasOperation.\(kind.rawValue)"
                    ) { beginModelingOperation(kind) }
                }
            }
            .padding(WorkspaceToolPaletteMetrics.containerPadding)
        }
        .scrollIndicators(.hidden)
        .frame(width: WorkspaceToolPaletteMetrics.buttonSize + 2 * WorkspaceToolPaletteMetrics.containerPadding)
        .frame(maxHeight: WorkspaceToolPaletteMetrics.defaultHeight)
        .viewportCanvasCapsuleGlassChrome()
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CanvasToolPalette")
    }

    private func toolPaletteButton(_ tool: ModelingTool) -> some View {
        return paletteButton(
            title: tool == .solid ? solidShape.rawValue : tool.title,
            hint: hintTitle(for: tool),
            symbol: tool == .solid ? solidShape.systemImage : tool.systemImage,
            isSelected: selectedOperation == nil && selectedTool == tool,
            identifier: accessibilityIdentifier(tool)
        ) {
            if tool == .solid {
                isSolidPickerPresented = true
            } else {
                activate(tool)
            }
        }
        .accessibilityHint(tool == .solid ? "Create Box, Sphere, or Cylinder" : tool.summary)
    }

    /// The hovered name, carrying the menu key so the shortcut is discoverable
    /// from the control it duplicates. A tool without a key shows none.
    private func hintTitle(for tool: ModelingTool) -> String {
        if tool == .solid { return "Solid · Box / Sphere / Cylinder" }
        guard let key = tool.menuKeyEquivalent else {
            return tool.title
        }
        return "\(tool.title)  \u{2318}\(key)"
    }

    private func paletteButton(
        title: String, hint: String, symbol: String, isSelected: Bool,
        identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
            .font(.system(size: WorkspaceToolPaletteMetrics.iconSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.72))
            .frame(
                width: WorkspaceToolPaletteMetrics.buttonSize,
                height: WorkspaceToolPaletteMetrics.buttonSize
            )
            .background {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.001))
            }
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.accentColor.opacity(0.56),
                            lineWidth: WorkspaceToolPaletteMetrics.selectedStrokeWidth
                        )
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(WorkspaceToolNameHint(title: hint, edge: .trailing))
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Available")
        .accessibilityIdentifier(identifier)
    }
}
