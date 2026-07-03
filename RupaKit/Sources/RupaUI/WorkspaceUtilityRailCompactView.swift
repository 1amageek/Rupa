import SwiftUI

struct WorkspaceUtilityRailCompactView: View {
    var selectionScope: WorkspaceSelectionScope
    var isGridSnapEnabled: Bool
    var isObjectTargetingEnabled: Bool
    var constructionPlaneTitle: String
    var isConstructionPlaneActive: Bool
    var surfaceAnalysisTitle: String
    var isSurfaceAnalysisActive: Bool
    var diagnosticTitle: String
    var hasDiagnostics: Bool
    var expand: () -> Void

    var body: some View {
        VStack(spacing: WorkspaceUtilityRailLayout.compactButtonSpacing) {
            WorkspaceUtilityRailCompactButton(
                systemImage: "slider.horizontal.3",
                help: "Show Canvas Controls",
                accessibilityIdentifier: "WorkspaceUtilityRail.expand",
                action: expand
            )

            WorkspaceUtilityRailCompactDivider()

            WorkspaceUtilityRailCompactButton(
                systemImage: selectionScope.systemImage,
                help: "Selection Scope: \(selectionScope.title)",
                accessibilityIdentifier: "WorkspaceUtilityRail.selection",
                isActive: selectionScope != .object,
                action: expand
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "grid",
                help: snapHelp,
                accessibilityIdentifier: "WorkspaceUtilityRail.snap",
                isActive: isGridSnapEnabled || isObjectTargetingEnabled,
                action: expand
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "square.grid.2x2",
                help: "Construction Plane: \(constructionPlaneTitle)",
                accessibilityIdentifier: "WorkspaceUtilityRail.plane",
                isActive: isConstructionPlaneActive,
                action: expand
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "waveform.path.ecg",
                help: "Surface Analysis: \(surfaceAnalysisTitle)",
                accessibilityIdentifier: "WorkspaceUtilityRail.analysis",
                isActive: isSurfaceAnalysisActive,
                action: expand
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "exclamationmark.triangle",
                help: "Scene Diagnostics: \(diagnosticTitle)",
                accessibilityIdentifier: "WorkspaceUtilityRail.scene",
                isActive: hasDiagnostics,
                hasWarning: hasDiagnostics,
                action: expand
            )
        }
        .padding(WorkspaceUtilityRailLayout.collapsedContentPadding)
        .frame(width: WorkspaceUtilityRailLayout.collapsedWidth)
        .workspaceGlassContainer()
        .accessibilityIdentifier("WorkspaceUtilityRail.collapsed")
    }

    private var snapHelp: String {
        "Snap: Grid \(isGridSnapEnabled ? "On" : "Off"), Object \(isObjectTargetingEnabled ? "On" : "Off")"
    }
}

private struct WorkspaceUtilityRailCompactDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 18, height: 1)
            .padding(.vertical, 1)
    }
}

private struct WorkspaceUtilityRailCompactButton: View {
    var systemImage: String
    var help: String
    var accessibilityIdentifier: String
    var isActive: Bool = false
    var hasWarning: Bool = false
    var action: () -> Void

    var body: some View {
        let tint = hasWarning
            ? Color.orange
            : (isActive ? Color.accentColor : Color.primary.opacity(0.72))
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(
                    width: WorkspaceUtilityRailLayout.compactButtonSize.width,
                    height: WorkspaceUtilityRailLayout.compactButtonSize.height
                )
                .background {
                    RoundedRectangle(
                        cornerRadius: WorkspaceChromeControlMetrics.cornerRadius,
                        style: .continuous
                    )
                    .fill((isActive || hasWarning) ? tint.opacity(0.16) : Color.primary.opacity(0.06))
                }
                .overlay(alignment: .topTrailing) {
                    if isActive || hasWarning {
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .padding(4)
                    }
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
}
