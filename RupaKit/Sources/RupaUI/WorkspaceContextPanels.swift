import RupaCore
import SwiftUI

@MainActor
struct WorkspacePolygonContextPanel<DimensionInputField: View>: View {
    var tool: ModelingTool
    var state: PolygonToolState
    var planeTitle: String
    var axisTitle: String
    var referenceLineAnchorCount: Int
    var dimensionInputTitle: String
    var isGridSnapEnabled: Bool
    var decreaseSideCount: () -> Void
    var increaseSideCount: () -> Void
    var toggleSizingMode: () -> Void
    var toggleInclinationMode: () -> Void
    var toggleKnifeMode: () -> Void
    @ViewBuilder var dimensionInputField: () -> DimensionInputField

    var body: some View {
        workspaceStatusChip(
            tool.title,
            systemImage: tool.systemImage,
            tint: .accentColor
        )

        workspaceContextDivider

        workspaceValuePill(
            "Sides",
            "\(state.sideCount)",
            accessibilityIdentifier: "WorkspacePolygon.sides"
        )

        workspaceIconButton(
            systemImage: "minus",
            help: "Decrease Polygon Sides",
            accessibilityIdentifier: "WorkspacePolygon.decreaseSides",
            action: decreaseSideCount
        )
        .disabled(!state.canDecreaseSideCount)

        workspaceIconButton(
            systemImage: "plus",
            help: "Increase Polygon Sides",
            accessibilityIdentifier: "WorkspacePolygon.increaseSides",
            action: increaseSideCount
        )
        .disabled(!state.canIncreaseSideCount)

        workspaceContextDivider

        workspaceValuePill(
            "Mode",
            state.sizingMode.statusTitle,
            accessibilityIdentifier: "WorkspacePolygon.sizingMode"
        )

        workspaceIconButton(
            systemImage: "circle.dashed",
            help: "Toggle Inscribed Circumscribed",
            accessibilityIdentifier: "WorkspacePolygon.toggleSizingMode",
            action: toggleSizingMode
        )

        workspaceValuePill(
            "Incline",
            state.inclinationMode.statusTitle,
            accessibilityIdentifier: "WorkspacePolygon.inclinationMode"
        )

        workspaceIconButton(
            systemImage: "arrow.up.and.down",
            help: "Toggle Polygon Inclination",
            accessibilityIdentifier: "WorkspacePolygon.toggleInclinationMode",
            action: toggleInclinationMode
        )

        workspaceContextDivider

        workspaceValuePill(
            "Knife",
            state.cutsFaces ? "On" : "Off",
            accessibilityIdentifier: "WorkspacePolygon.knifeMode"
        )

        workspaceIconButton(
            systemImage: "scissors",
            help: "Toggle Polygon Knife",
            accessibilityIdentifier: "WorkspacePolygon.toggleKnifeMode",
            action: toggleKnifeMode
        )

        workspaceValuePill("Plane", planeTitle)
        workspaceValuePill(
            "Axis",
            axisTitle,
            accessibilityIdentifier: "WorkspaceSketch.axisConstraint"
        )
        workspaceValuePill(
            "Refs",
            "\(referenceLineAnchorCount)",
            accessibilityIdentifier: "WorkspaceSketch.referenceLines"
        )
        workspaceValuePill(
            "Input",
            dimensionInputTitle,
            accessibilityIdentifier: "WorkspaceSketch.dimensionInputFocus"
        )
        dimensionInputField()
        workspaceValuePill("Grid", isGridSnapEnabled ? "On" : "Off")
    }
}

@MainActor
struct WorkspaceSweepContextPanel: View {
    var preview: SweepSelectionPreview
    var sectionLabel: String
    var pathLabel: String

    var body: some View {
        workspaceStatusChip(
            preview.isReady ? "Sweep Source" : "Sweep Setup",
            systemImage: ModelingTool.sweep.systemImage,
            tint: preview.isReady ? .accentColor : .secondary
        )

        workspaceContextDivider

        workspaceValuePill(
            "Section",
            sectionLabel,
            accessibilityIdentifier: "WorkspaceSweep.section"
        )
        workspaceValuePill(
            "Path",
            pathLabel,
            accessibilityIdentifier: "WorkspaceSweep.path"
        )
        workspaceValuePill(
            "Guides",
            "\(preview.guideFeatureIDs.count)",
            accessibilityIdentifier: "WorkspaceSweep.guides"
        )

        workspaceContextDivider

        workspaceValuePill(
            "Status",
            preview.statusTitle,
            accessibilityIdentifier: "WorkspaceSweep.status"
        )
    }
}
