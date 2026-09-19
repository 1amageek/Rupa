import RupaCore
import RupaRendering
import SwiftUI

struct WorkspaceToolPalette: View {
    var selectedTool: ModelingTool
    var activate: (ModelingTool) -> Void
    var accessibilityIdentifier: (ModelingTool) -> String

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: WorkspaceToolPaletteMetrics.itemSpacing) {
                ForEach(ModelingTool.allCases) { tool in
                    toolPaletteButton(tool)
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
        let isSelected = selectedTool == tool

        return Button {
            activate(tool)
        } label: {
            toolPaletteIcon(tool, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .modifier(WorkspaceToolNameHint(title: hintTitle(for: tool), edge: .trailing))
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.summary)
        .accessibilityValue(isSelected ? "Selected" : "Available")
        .accessibilityIdentifier(accessibilityIdentifier(tool))
    }

    /// The hovered name, carrying the menu key so the shortcut is discoverable
    /// from the control it duplicates. A tool without a key shows none.
    private func hintTitle(for tool: ModelingTool) -> String {
        guard let key = tool.menuKeyEquivalent else {
            return tool.title
        }
        return "\(tool.title)  \u{2318}\(key)"
    }

    private func toolPaletteIcon(_ tool: ModelingTool, isSelected: Bool) -> some View {
        Image(systemName: tool.systemImage)
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
}
