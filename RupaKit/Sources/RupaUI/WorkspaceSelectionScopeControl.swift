import SwiftUI

struct WorkspaceSelectionScopeControlLayout: Equatable {
    static let columnCount = 3
    static let spacing: CGFloat = 6.0
    static let buttonSize = CGSize(width: 48.0, height: 42.0)

    static var contentWidth: CGFloat {
        CGFloat(columnCount) * buttonSize.width
            + CGFloat(columnCount - 1) * spacing
    }

    static func rowCount(itemCount: Int) -> Int {
        guard itemCount > 0 else {
            return 0
        }
        return (itemCount + columnCount - 1) / columnCount
    }
}

struct WorkspaceSelectionScopeControl: View {
    @Binding var selection: WorkspaceSelectionScope

    var body: some View {
        LazyVGrid(
            columns: gridColumns,
            alignment: .leading,
            spacing: WorkspaceSelectionScopeControlLayout.spacing
        ) {
            ForEach(WorkspaceSelectionScope.allCases) { scope in
                scopeButton(scope)
            }
        }
        .frame(width: WorkspaceSelectionScopeControlLayout.contentWidth, alignment: .leading)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .fixed(WorkspaceSelectionScopeControlLayout.buttonSize.width),
                spacing: WorkspaceSelectionScopeControlLayout.spacing
            ),
            count: WorkspaceSelectionScopeControlLayout.columnCount
        )
    }

    private func scopeButton(_ scope: WorkspaceSelectionScope) -> some View {
        let isSelected = selection == scope
        let isEnabled = scope.isEnabled
        return Button {
            selection = scope
        } label: {
            VStack(spacing: 4) {
                Image(systemName: scope.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(scope.shortTitle)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(foregroundStyle(isSelected: isSelected, isEnabled: isEnabled))
            .frame(
                width: WorkspaceSelectionScopeControlLayout.buttonSize.width,
                height: WorkspaceSelectionScopeControlLayout.buttonSize.height
            )
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fillStyle(isSelected: isSelected, isEnabled: isEnabled))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(borderStyle(isSelected: isSelected, isEnabled: isEnabled), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(scope.help)
        .accessibilityLabel(scope.title)
        .accessibilityValue(accessibilityValue(scope, isSelected: isSelected))
        .accessibilityIdentifier("WorkspaceSelectionScope.\(scope.rawValue)")
    }

    private func foregroundStyle(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return .secondary
        }
        return isSelected ? .accentColor : Color.primary.opacity(0.72)
    }

    private func fillStyle(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return Color.primary.opacity(0.04)
        }
        return isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)
    }

    private func borderStyle(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return Color.primary.opacity(0.08)
        }
        return isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10)
    }

    private func accessibilityValue(
        _ scope: WorkspaceSelectionScope,
        isSelected: Bool
    ) -> String {
        guard scope.isEnabled else {
            return "Unavailable"
        }
        return isSelected ? "Selected" : "Available"
    }
}
