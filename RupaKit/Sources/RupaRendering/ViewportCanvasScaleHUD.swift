import RupaCore
import SwiftUI

struct ViewportCanvasScaleHUD: View {
    var scaleReadout: ViewportProjectedGrid.ScaleReadout
    var zoomPercentageText: String
    var menuState: ViewportCanvasScaleMenuState
    var onSelectPreset: ((WorkspaceScalePreset) -> Void)?
    var onAction: ((ViewportCanvasScaleMenuState.Action) -> Void)?

    var body: some View {
        Menu {
            menuContent
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Canvas Scale")
        .accessibilityValue(menuState.accessibilityText)
        .accessibilityIdentifier("CanvasScaleHUD")
    }

    nonisolated static func estimatedWidth(
        scaleReadout: ViewportProjectedGrid.ScaleReadout,
        zoomPercentageText: String
    ) -> CGFloat {
        let textSegments = [
            scaleReadout.minorStep.displayUnit.symbol,
            scaleReadout.canvasHUDText,
            zoomPercentageText,
        ]

        let dividerCount = max(0, textSegments.count - 1)
        let childCount = 1 + textSegments.count + dividerCount
        let averageCaptionGlyphWidth: CGFloat = 7.0
        let iconWidth: CGFloat = 14.0
        let textWidth = textSegments.reduce(CGFloat.zero) { width, segment in
            width + CGFloat(segment.count) * averageCaptionGlyphWidth
        }
        let dividerWidth = CGFloat(dividerCount)
        let spacingWidth = CGFloat(max(0, childCount - 1))
            * ViewportCanvasChromeMetrics.topControlItemSpacing
        let width = iconWidth
            + textWidth
            + dividerWidth
            + spacingWidth
            + ViewportCanvasChromeMetrics.topControlHorizontalPadding * 2.0
        return min(
            max(width.rounded(.up), ViewportCanvasChromeLayout.minimumViewportBadgeWidth),
            ViewportCanvasChromeMetrics.topControlMaximumWidth
        )
    }

    @ViewBuilder
    private var menuContent: some View {
        Section("Canvas Scale") {
            ForEach(menuState.rows) { row in
                Text("\(row.title): \(row.value)")
            }
            if menuState.isVisualStepCapped {
                Text("Visual grid capped by line budget")
            }
        }

        if !menuState.presetOptions.isEmpty, onSelectPreset != nil {
            Section("Scale Presets") {
                ForEach(menuState.presetOptions) { option in
                    Button {
                        onSelectPreset?(option.preset)
                    } label: {
                        HStack {
                            Text(option.menuTitle)
                            if option.isSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .help("Comfortable model span \(option.comfortTitle)")
                    .accessibilityIdentifier(option.accessibilityIdentifier)
                }
            }
        }

        if !menuState.availableActions.isEmpty, onAction != nil {
            Section("Workspace Scale") {
                ForEach(menuState.availableActions) { action in
                    actionButton(action)
                }
            }
        }
    }

    private var label: some View {
        HStack(spacing: ViewportCanvasChromeMetrics.topControlItemSpacing) {
            Image(systemName: "scope")
                .symbolRenderingMode(.hierarchical)
            Text(scaleReadout.minorStep.displayUnit.symbol)
                .font(.system(.caption, design: .monospaced))
            Divider()
                .frame(height: ViewportCanvasChromeMetrics.topControlDividerHeight)
            Text(scaleReadout.canvasHUDText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.middle)
            Divider()
                .frame(height: ViewportCanvasChromeMetrics.topControlDividerHeight)
            Text(zoomPercentageText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, ViewportCanvasChromeMetrics.topControlHorizontalPadding)
        .frame(
            height: ViewportCanvasChromeLayout.viewportBadgeHeight,
            alignment: .leading
        )
        .viewportCanvasTopChrome()
    }

    private func actionButton(
        _ action: ViewportCanvasScaleMenuState.Action
    ) -> some View {
        Button {
            onAction?(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }
}
