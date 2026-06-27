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

@MainActor
struct WorkspaceDimensionContextPanel<DimensionInputField: View>: View {
    var targetTitle: String
    var kindTitle: String
    var sourceTitle: String
    var itemTitle: String
    var valueTitle: String
    var isInputModeActive: Bool
    var canMoveBetweenDimensions: Bool
    var canCommit: Bool
    var focusPrevious: () -> Void
    var activateInputMode: () -> Void
    var focusNext: () -> Void
    var confirm: () -> Void
    var cancel: () -> Void
    @ViewBuilder var inputField: () -> DimensionInputField

    var body: some View {
        workspaceStatusChip(
            "Dimension",
            systemImage: "ruler",
            tint: .accentColor
        )
        workspaceContextDivider
        workspaceValuePill(
            "Target",
            targetTitle,
            accessibilityIdentifier: "WorkspaceDimension.target"
        )
        workspaceValuePill(
            "Kind",
            kindTitle,
            accessibilityIdentifier: "WorkspaceDimension.kind"
        )
        workspaceValuePill(
            "Source",
            sourceTitle,
            accessibilityIdentifier: "WorkspaceDimension.source"
        )
        workspaceValuePill(
            "Item",
            itemTitle,
            accessibilityIdentifier: "WorkspaceDimension.index"
        )

        if isInputModeActive {
            inputField()
        } else {
            workspaceValuePill(
                "Value",
                valueTitle,
                accessibilityIdentifier: "WorkspaceDimension.value"
            )
        }

        workspaceIconButton(
            systemImage: "chevron.left",
            help: "Previous Dimension",
            accessibilityIdentifier: "WorkspaceDimension.previous",
            action: focusPrevious
        )
        .disabled(!canMoveBetweenDimensions)

        workspaceIconButton(
            systemImage: "keyboard",
            help: "Enter Dimension Input",
            accessibilityIdentifier: "WorkspaceDimension.input",
            action: activateInputMode
        )
        .disabled(isInputModeActive)

        workspaceIconButton(
            systemImage: "chevron.right",
            help: "Next Dimension",
            accessibilityIdentifier: "WorkspaceDimension.next",
            action: focusNext
        )
        .disabled(!canMoveBetweenDimensions)

        workspaceIconButton(
            systemImage: "checkmark",
            help: "Confirm Dimension",
            accessibilityIdentifier: "WorkspaceDimension.confirm",
            action: confirm
        )
        .disabled(!canCommit)

        workspaceIconButton(
            systemImage: "xmark",
            help: "Cancel Dimension",
            accessibilityIdentifier: "WorkspaceDimension.cancel",
            action: cancel
        )
    }
}

@MainActor
struct WorkspaceSlotContextPanel: View {
    var isActive: Bool
    var widthTitle: String
    var inputModeTitle: String
    var create: () -> Void

    var body: some View {
        workspaceStatusChip(
            "Slot",
            systemImage: "capsule",
            tint: isActive ? .accentColor : .secondary
        )

        workspaceValuePill(
            "Width",
            widthTitle,
            accessibilityIdentifier: "WorkspaceSlot.width"
        )
        workspaceValuePill(
            "Input",
            inputModeTitle,
            accessibilityIdentifier: "WorkspaceSlot.inputMode"
        )

        workspaceIconButton(
            systemImage: "capsule",
            help: "Create Slot Profile",
            accessibilityIdentifier: "WorkspaceSlot.create",
            action: create
        )
    }
}

@MainActor
struct WorkspaceEdgeOffsetContextPanel: View {
    var isSupported: Bool
    var distanceTitle: String
    var gapFillTitle: String
    var inputModeTitle: String
    var lockedDistanceTitle: String
    var supportTitle: String
    var offset: () -> Void

    var body: some View {
        workspaceStatusChip(
            "Offset Edge",
            systemImage: "arrow.up.left.and.arrow.down.right",
            tint: isSupported ? .accentColor : .orange
        )

        workspaceValuePill(
            "Distance",
            distanceTitle,
            accessibilityIdentifier: "WorkspaceEdgeOffset.distance"
        )
        workspaceValuePill(
            "Gap",
            gapFillTitle,
            accessibilityIdentifier: "WorkspaceEdgeOffset.gapFill"
        )
        workspaceValuePill(
            "Input",
            inputModeTitle,
            accessibilityIdentifier: "WorkspaceEdgeOffset.inputMode"
        )
        workspaceValuePill(
            "Lock",
            lockedDistanceTitle,
            accessibilityIdentifier: "WorkspaceEdgeOffset.lockedDistance"
        )
        workspaceValuePill(
            "Support",
            supportTitle,
            accessibilityIdentifier: "WorkspaceEdgeOffset.support"
        )

        workspaceIconButton(
            systemImage: "arrow.up.left.and.arrow.down.right",
            help: "Offset Edge",
            accessibilityIdentifier: "WorkspaceEdgeOffset.offset",
            action: offset
        )
    }
}

@MainActor
struct WorkspaceRegionOffsetContextPanel: View {
    var distanceTitle: String
    var gapFillTitle: String
    var inputModeTitle: String
    var lockedDistanceTitle: String
    var modeTitle: String
    var offsetInward: () -> Void
    var offsetOutward: () -> Void

    var body: some View {
        workspaceStatusChip(
            "Offset Region",
            systemImage: "arrow.up.left.and.arrow.down.right",
            tint: .accentColor
        )

        workspaceValuePill(
            "Distance",
            distanceTitle,
            accessibilityIdentifier: "WorkspaceRegionOffset.distance"
        )
        workspaceValuePill(
            "Gap",
            gapFillTitle,
            accessibilityIdentifier: "WorkspaceRegionOffset.gapFill"
        )
        workspaceValuePill(
            "Input",
            inputModeTitle,
            accessibilityIdentifier: "WorkspaceRegionOffset.inputMode"
        )
        workspaceValuePill(
            "Lock",
            lockedDistanceTitle,
            accessibilityIdentifier: "WorkspaceRegionOffset.lockedDistance"
        )
        workspaceValuePill(
            "Mode",
            modeTitle,
            accessibilityIdentifier: "WorkspaceRegionOffset.regionMode"
        )

        workspaceIconButton(
            systemImage: "minus.circle",
            help: "Offset Inward",
            accessibilityIdentifier: "WorkspaceRegionOffset.inward",
            action: offsetInward
        )

        workspaceIconButton(
            systemImage: "plus.circle",
            help: "Offset Outward",
            accessibilityIdentifier: "WorkspaceRegionOffset.outward",
            action: offsetOutward
        )
    }
}
