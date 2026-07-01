import SwiftUI

struct WorkspaceSelectionScopeControlLayout: Equatable {
    static let columnCount = 6
    static let spacing: CGFloat = 2.0
    static let buttonSize = CGSize(width: 25.0, height: 26.0)
    static let iconSize: CGFloat = 12.0
    static let cornerRadius: CGFloat = 6.0

    static var contentWidth: CGFloat {
        CGFloat(columnCount) * buttonSize.width
            + CGFloat(columnCount - 1) * spacing
    }

    static var fitsInUtilityRail: Bool {
        contentWidth <= WorkspaceUtilityRailLayout.contentWidth
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
        HStack(spacing: WorkspaceSelectionScopeControlLayout.spacing) {
            ForEach(WorkspaceSelectionScope.allCases) { scope in
                scopeButton(scope)
            }
        }
        .frame(
            width: WorkspaceSelectionScopeControlLayout.contentWidth,
            height: WorkspaceSelectionScopeControlLayout.buttonSize.height,
            alignment: .leading
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    private func scopeButton(_ scope: WorkspaceSelectionScope) -> some View {
        let isSelected = selection == scope
        let isEnabled = scope.isEnabled
        return Button {
            selection = scope
        } label: {
            Image(systemName: scope.systemImage)
                .font(.system(size: WorkspaceSelectionScopeControlLayout.iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(foregroundStyle(isSelected: isSelected, isEnabled: isEnabled))
                .frame(
                    width: WorkspaceSelectionScopeControlLayout.buttonSize.width,
                    height: WorkspaceSelectionScopeControlLayout.buttonSize.height
                )
                .background {
                    RoundedRectangle(cornerRadius: WorkspaceSelectionScopeControlLayout.cornerRadius, style: .continuous)
                        .fill(fillStyle(isSelected: isSelected, isEnabled: isEnabled))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: WorkspaceSelectionScopeControlLayout.cornerRadius, style: .continuous)
                        .strokeBorder(borderStyle(isSelected: isSelected, isEnabled: isEnabled), lineWidth: 1)
                }
                .contentShape(
                    RoundedRectangle(cornerRadius: WorkspaceSelectionScopeControlLayout.cornerRadius, style: .continuous)
                )
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
