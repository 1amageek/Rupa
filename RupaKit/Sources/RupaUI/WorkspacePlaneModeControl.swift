import SwiftUI

enum WorkspacePlaneModeControlLayout: Equatable {
    static let columnCount = WorkspacePlaneMode.allCases.count
    static let spacing: CGFloat = WorkspaceCanvasHeaderLayout.seatItemSpacing
    static let buttonSize = CGSize(
        width: 31.0,
        height: WorkspaceCanvasHeaderLayout.controlSize.height
    )
    static let cornerRadius: CGFloat = 6.0

    static var contentWidth: CGFloat {
        CGFloat(columnCount) * buttonSize.width + CGFloat(columnCount - 1) * spacing
    }
}

struct WorkspacePlaneModeControl: View {
    @Binding var selection: WorkspacePlaneMode

    var body: some View {
        HStack(spacing: WorkspacePlaneModeControlLayout.spacing) {
            ForEach(WorkspacePlaneMode.allCases) { mode in
                modeButton(mode)
            }
        }
        .frame(
            width: WorkspacePlaneModeControlLayout.contentWidth,
            height: WorkspacePlaneModeControlLayout.buttonSize.height,
            alignment: .leading
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    private func modeButton(_ mode: WorkspacePlaneMode) -> some View {
        let isSelected = selection == mode
        return Button {
            selection = mode
        } label: {
            Text(mode.shortTitle)
                .font(.caption.weight(.semibold))
                .monospaced()
                .frame(
                    width: WorkspacePlaneModeControlLayout.buttonSize.width,
                    height: WorkspacePlaneModeControlLayout.buttonSize.height
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: WorkspacePlaneModeControlLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.76))
                .background {
                    RoundedRectangle(cornerRadius: WorkspacePlaneModeControlLayout.cornerRadius, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: WorkspacePlaneModeControlLayout.cornerRadius, style: .continuous)
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
