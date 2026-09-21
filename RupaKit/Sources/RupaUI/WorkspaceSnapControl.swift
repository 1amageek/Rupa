import SwiftUI

enum WorkspaceSnapControlLayout: Equatable {
    static let columnCount = 4
    static let spacing: CGFloat = WorkspaceCanvasHeaderLayout.seatItemSpacing
    static let buttonSize = WorkspaceCanvasHeaderLayout.controlSize
    static let cornerRadius: CGFloat = 6.0
    static let iconSize: CGFloat = 12.0

    static var contentWidth: CGFloat {
        CGFloat(columnCount) * buttonSize.width + CGFloat(columnCount - 1) * spacing
    }
}

/// The four snaps that decide where a click lands, as one header seat.
///
/// The rail spelled each of these out with a caption under its icon, which a
/// bar cannot afford. The seat is icon-first instead: the name reaches the
/// user through the tooltip and the header's hover hint, and the identifiers
/// stay the ones the snaps already published.
struct WorkspaceSnapControl: View {
    @Binding var isGridSnapEnabled: Bool
    @Binding var isObjectTargetingEnabled: Bool
    @Binding var isFixedGridVisualSpacing: Bool
    @Binding var isConstructionPlaneSnapEnabled: Bool

    var body: some View {
        HStack(spacing: WorkspaceSnapControlLayout.spacing) {
            toggle(
                isOn: $isGridSnapEnabled,
                systemImage: "grid",
                title: "Grid",
                help: "Grid Snap",
                accessibilityIdentifier: "WorkspaceSnap.grid"
            )
            toggle(
                isOn: $isObjectTargetingEnabled,
                systemImage: "dot.scope",
                title: "Object",
                help: "Object Targeting",
                accessibilityIdentifier: "WorkspaceSnap.object"
            )
            toggle(
                isOn: $isFixedGridVisualSpacing,
                systemImage: "lock",
                title: "Fixed",
                help: "Fixed Visual Grid",
                accessibilityIdentifier: "WorkspaceGrid.fixed"
            )
            toggle(
                isOn: $isConstructionPlaneSnapEnabled,
                systemImage: "square.grid.2x2",
                title: "2D",
                help: "2D Construction Plane Snap",
                accessibilityIdentifier: "WorkspacePlane.twoDSnap"
            )
        }
        .frame(
            width: WorkspaceSnapControlLayout.contentWidth,
            height: WorkspaceSnapControlLayout.buttonSize.height,
            alignment: .leading
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    private func toggle(
        isOn: Binding<Bool>,
        systemImage: String,
        title: String,
        help: String,
        accessibilityIdentifier: String
    ) -> some View {
        let isSelected = isOn.wrappedValue
        return Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: WorkspaceSnapControlLayout.iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(
                    width: WorkspaceSnapControlLayout.buttonSize.width,
                    height: WorkspaceSnapControlLayout.buttonSize.height
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: WorkspaceSnapControlLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.72))
                .background {
                    RoundedRectangle(
                        cornerRadius: WorkspaceSnapControlLayout.cornerRadius,
                        style: .continuous
                    )
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: WorkspaceSnapControlLayout.cornerRadius,
                        style: .continuous
                    )
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "On" : "Off")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
