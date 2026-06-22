import SwiftUI

struct WorkspaceSelectionScopeControl: View {
    @Binding var selection: WorkspaceSelectionScope

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WorkspaceSelectionScope.allCases) { scope in
                scopeButton(scope)
            }
        }
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
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(foregroundStyle(isSelected: isSelected, isEnabled: isEnabled))
            .frame(maxWidth: .infinity, minHeight: 42)
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
