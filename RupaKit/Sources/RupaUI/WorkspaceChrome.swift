import RupaCore
import SwiftUI

/// The metrics a header panel's content is laid out at.
///
/// A panel is presented in a popover, which sizes itself to what it contains,
/// so the width here is the one the panel asks for rather than a share of the
/// canvas.
enum WorkspaceCanvasPanelLayout {
    static let width: CGFloat = 220
    static let maximumHeight: CGFloat = 620
    static let contentPadding: CGFloat = 10
    static let sectionSpacing: CGFloat = 10
    static let sectionHeaderSpacing: CGFloat = 7

    static var contentWidth: CGFloat {
        width - contentPadding * 2
    }
}

@MainActor
func workspacePanelSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: WorkspaceCanvasPanelLayout.sectionHeaderSpacing) {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// Lays a panel row out as a secondary title and its value.
///
/// `accessibilityIdentifier` names the value `Text`, not the row. macOS gives
/// a row collapsed with `.accessibilityElement(children: .ignore)` the `Other`
/// role, which publishes the accessibility label and drops the accessibility
/// value, while a `Text` keeps `StaticText` and publishes its string as the
/// element's value. A caller whose value a test reads passes the identifier
/// here so the value stays readable.
@ViewBuilder
@MainActor
func workspaceValueRow(
    _ title: String,
    _ value: String,
    accessibilityIdentifier: String? = nil
) -> some View {
    let valueText = Text(value)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .monospacedDigit()
    HStack(spacing: 8) {
        Text(title)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 6)
        if let accessibilityIdentifier {
            valueText
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            valueText
        }
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
    .lineLimit(nil)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, WorkspaceChromeControlMetrics.horizontalPadding)
    .frame(minHeight: WorkspaceChromeControlMetrics.controlHeight)
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
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .monospacedDigit()
    } icon: {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(tint)
    .padding(.horizontal, WorkspaceChromeControlMetrics.horizontalPadding)
    .frame(minHeight: WorkspaceChromeControlMetrics.controlHeight)
    .background {
        RoundedRectangle(
            cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
            style: .continuous
        )
            .fill(tint.opacity(0.12))
    }
}

/// A prompt, a refusal and a failure all reach the user through the same chip, so the chip has to
/// say which one it is carrying before the sentence is read. The icon and the tint are that answer,
/// and they have to differ per severity or a command that would not run reads like an instruction.
func workspaceStatusSystemImage(for severity: EditorDiagnostic.Severity) -> String {
    switch severity {
    case .info:
        "info.circle"
    case .warning:
        "exclamationmark.triangle"
    case .error:
        "xmark.octagon"
    }
}

func workspaceStatusTint(for severity: EditorDiagnostic.Severity) -> Color {
    switch severity {
    case .info:
        .secondary
    case .warning:
        .orange
    case .error:
        .red
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
