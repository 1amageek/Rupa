import SwiftUI

enum WorkspaceUtilityRailLayout {
    static let width: CGFloat = expandedWidth
    static let expandedWidth: CGFloat = 178
    static let collapsedWidth: CGFloat = 38
    static let contentPadding: CGFloat = 8
    static let collapsedContentPadding: CGFloat = 6
    static let sectionSpacing: CGFloat = 8
    static let sectionHeaderSpacing: CGFloat = 7
    static let compactButtonSpacing: CGFloat = 5
    static let compactButtonSize = CGSize(width: 26.0, height: 26.0)

    static var contentWidth: CGFloat {
        expandedWidth - contentPadding * 2
    }

    static var collapsedContentWidth: CGFloat {
        collapsedWidth - collapsedContentPadding * 2
    }
}

@MainActor
func workspaceRailSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: WorkspaceUtilityRailLayout.sectionHeaderSpacing) {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

@MainActor
func workspaceToggleButton(
    isOn: Binding<Bool>,
    systemImage: String,
    title: String,
    help: String,
    accessibilityIdentifier: String
) -> some View {
    Button {
        isOn.wrappedValue.toggle()
    } label: {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.primary.opacity(0.72))
        .frame(maxWidth: .infinity, minHeight: 42)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isOn.wrappedValue ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.10),
                    lineWidth: 1
                )
        }
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(title)
    .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    .accessibilityIdentifier(accessibilityIdentifier)
}

@MainActor
func workspaceValueRow(_ title: String, _ value: String) -> some View {
    HStack(spacing: 8) {
        Text(title)
            .foregroundStyle(.secondary)
        Spacer(minLength: 6)
        Text(value)
            .lineLimit(1)
            .truncationMode(.middle)
            .monospacedDigit()
    }
    .font(.caption)
}

@ViewBuilder
@MainActor
func workspaceValuePill(
    _ title: String,
    _ value: String,
    accessibilityIdentifier: String? = nil
) -> some View {
    let pill = HStack(spacing: 5) {
        Text(title)
            .foregroundStyle(.secondary)
        if let accessibilityIdentifier {
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityLabel(title)
                .accessibilityValue(value)
        } else {
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
    .font(.caption)
    .lineLimit(1)
    .padding(.horizontal, WorkspaceChromeControlMetrics.horizontalPadding)
    .frame(height: WorkspaceChromeControlMetrics.controlHeight)
    .background {
        RoundedRectangle(
            cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
            style: .continuous
        )
            .fill(Color.primary.opacity(0.06))
    }

    pill
}

@MainActor
func workspaceStatusChip(
    _ title: String,
    systemImage: String,
    tint: Color
) -> some View {
    Label {
        Text(title)
            .lineLimit(1)
            .monospacedDigit()
    } icon: {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(tint)
    .padding(.horizontal, WorkspaceChromeControlMetrics.horizontalPadding)
    .frame(height: WorkspaceChromeControlMetrics.controlHeight)
    .background {
        RoundedRectangle(
            cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
            style: .continuous
        )
            .fill(tint.opacity(0.12))
    }
}

@MainActor
func workspaceIconButton(
    systemImage: String,
    help: String,
    accessibilityIdentifier: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .frame(
                width: WorkspaceChromeControlMetrics.iconButtonSize.width,
                height: WorkspaceChromeControlMetrics.iconButtonSize.height
            )
            .background {
                RoundedRectangle(
                    cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                    style: .continuous
                )
                    .fill(Color.primary.opacity(0.06))
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                    style: .continuous
                )
            )
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
    .accessibilityIdentifier(accessibilityIdentifier)
}

@MainActor
var workspaceDivider: some View {
    WorkspaceDivider(height: WorkspaceChromeControlMetrics.dividerHeight)
}

@MainActor
var workspaceContextDivider: some View {
    WorkspaceDivider(height: WorkspaceChromeControlMetrics.dividerHeight)
}

private struct WorkspaceDivider: View {
    var height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: height)
    }
}
