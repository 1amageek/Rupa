import SwiftUI

enum WorkspaceUtilityRailDestination: String, CaseIterable, Hashable, Sendable {
    case controls
    case selection
    case snap
    case plane
    case analysis
    case views
    case scene

    var title: String {
        switch self {
        case .controls:
            "Canvas Controls"
        case .selection:
            "Selection"
        case .snap:
            "Snap"
        case .plane:
            "Construction Plane"
        case .analysis:
            "Surface Analysis"
        case .views:
            "Saved Views"
        case .scene:
            "Scene Diagnostics"
        }
    }
}

struct WorkspaceUtilityRailCompactView: View {
    var selectionScope: WorkspaceSelectionScope
    var isGridSnapEnabled: Bool
    var isObjectTargetingEnabled: Bool
    var constructionPlaneTitle: String
    var isConstructionPlaneActive: Bool
    var surfaceAnalysisTitle: String
    var isSurfaceAnalysisActive: Bool
    var savedViewCount: Int
    var diagnosticTitle: String
    var hasDiagnostics: Bool
    var expand: (WorkspaceUtilityRailDestination) -> Void

    var body: some View {
        VStack(spacing: WorkspaceUtilityRailLayout.compactButtonSpacing) {
            WorkspaceUtilityRailCompactButton(
                systemImage: "slider.horizontal.3",
                title: WorkspaceUtilityRailDestination.controls.title,
                help: "Show Canvas Controls",
                accessibilityIdentifier: "WorkspaceUtilityRail.expand",
                action: { expand(.controls) }
            )

            WorkspaceUtilityRailCompactDivider()

            WorkspaceUtilityRailCompactButton(
                systemImage: selectionScope.systemImage,
                title: WorkspaceUtilityRailDestination.selection.title,
                help: "Selection Scope: \(selectionScope.title)",
                accessibilityIdentifier: "WorkspaceUtilityRail.selection",
                isActive: selectionScope != .object,
                action: { expand(.selection) }
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "grid",
                title: WorkspaceUtilityRailDestination.snap.title,
                help: snapHelp,
                accessibilityIdentifier: "WorkspaceUtilityRail.snap",
                isActive: isGridSnapEnabled || isObjectTargetingEnabled,
                action: { expand(.snap) }
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "square.grid.2x2",
                title: WorkspaceUtilityRailDestination.plane.title,
                help: "Construction Plane: \(constructionPlaneTitle)",
                accessibilityIdentifier: "WorkspaceUtilityRail.plane",
                isActive: isConstructionPlaneActive,
                action: { expand(.plane) }
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "waveform.path.ecg",
                title: WorkspaceUtilityRailDestination.analysis.title,
                help: "Surface Analysis: \(surfaceAnalysisTitle)",
                accessibilityIdentifier: "WorkspaceUtilityRail.analysis",
                isActive: isSurfaceAnalysisActive,
                action: { expand(.analysis) }
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "viewfinder",
                title: WorkspaceUtilityRailDestination.views.title,
                help: "Saved Views: \(savedViewCount)",
                accessibilityIdentifier: "WorkspaceUtilityRail.views",
                isActive: savedViewCount > 0,
                action: { expand(.views) }
            )
            WorkspaceUtilityRailCompactButton(
                systemImage: "exclamationmark.triangle",
                title: WorkspaceUtilityRailDestination.scene.title,
                help: "Scene Diagnostics: \(diagnosticTitle)",
                accessibilityIdentifier: "WorkspaceUtilityRail.scene",
                isActive: hasDiagnostics,
                hasWarning: hasDiagnostics,
                action: { expand(.scene) }
            )
        }
        .padding(WorkspaceUtilityRailLayout.collapsedContentPadding)
        .frame(width: WorkspaceUtilityRailLayout.collapsedWidth)
        .workspaceGlassContainer()
        .accessibilityElement(children: .contain)
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
    var title: String
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
        .modifier(WorkspaceToolNameHint(title: title, edge: .leading))
        .accessibilityLabel(title)
        .accessibilityHint(help)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
