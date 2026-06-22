import SwiftUI

struct WorkspacePlaneModeControl: View {
    @Binding var selection: WorkspacePlaneMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WorkspacePlaneMode.allCases) { mode in
                modeButton(mode)
            }
        }
    }

    private func modeButton(_ mode: WorkspacePlaneMode) -> some View {
        let isSelected = selection == mode
        return Button {
            selection = mode
        } label: {
            Text(mode.shortTitle)
                .font(.caption.weight(.semibold))
                .monospaced()
                .frame(maxWidth: .infinity, minHeight: 26)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.76))
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .help(mode.help)
        .accessibilityLabel(mode.title)
        .accessibilityValue(isSelected ? "Selected" : "Available")
        .accessibilityIdentifier("WorkspacePlane.\(mode.rawValue)")
    }
}
