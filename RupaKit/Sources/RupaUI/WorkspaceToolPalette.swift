import RupaCore
import SwiftUI

struct WorkspaceToolPalette: View {
    var selectedTool: ModelingTool
    var activate: (ModelingTool) -> Void
    var help: (ModelingTool) -> String
    var accessibilityIdentifier: (ModelingTool) -> String

    var body: some View {
        VStack(spacing: 6) {
            ForEach(ModelingTool.allCases) { tool in
                toolPaletteButton(tool)
            }
        }
        .padding(6)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
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
        .help(help(tool))
        .accessibilityLabel(tool.title)
        .accessibilityValue(isSelected ? "Selected" : "Available")
        .accessibilityIdentifier(accessibilityIdentifier(tool))
    }

    private func toolPaletteIcon(_ tool: ModelingTool, isSelected: Bool) -> some View {
        Image(systemName: tool.systemImage)
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.72))
            .frame(width: 36, height: 36)
            .background {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.001))
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.56) : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            }
            .contentShape(Circle())
    }
}
