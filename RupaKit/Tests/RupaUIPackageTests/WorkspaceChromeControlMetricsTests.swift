@testable import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceChromeControlsShareCompactCanvasHeight() {
    #expect(WorkspaceChromeControlMetrics.containerHeight == ViewportCanvasChromeMetrics.topControlHeight)
    #expect(WorkspaceChromeControlMetrics.iconButtonSize.width == WorkspaceChromeControlMetrics.controlHeight)
    #expect(WorkspaceChromeControlMetrics.iconButtonSize.height == WorkspaceChromeControlMetrics.controlHeight)
    #expect(WorkspaceChromeControlMetrics.controlHeight <= ViewportCanvasChromeMetrics.topControlHeight - 8.0)
    #expect(WorkspaceChromeControlMetrics.dividerHeight <= WorkspaceChromeControlMetrics.controlHeight)
    let containedHeight = WorkspaceChromeControlMetrics.controlHeight
        + WorkspaceChromeControlMetrics.containerVerticalPadding * 2.0
    #expect(abs(containedHeight - WorkspaceChromeControlMetrics.containerHeight) < 1.0e-9)
    #expect(ViewportCanvasChromeMetrics.topControlHeight == 28.0)
    #expect(ViewportCanvasChromeMetrics.topControlContentHeight == 20.0)
    #expect(ViewportCanvasChromeMetrics.edgePadding == 5.0)
    #expect(ViewportCanvasChromeMetrics.topControlItemSpacing == ViewportCanvasChromeMetrics.edgePadding)
    #expect(ViewportCanvasChromeMetrics.topControlMaximumWidth == 180.0)
    #expect(WorkspaceChromeControlMetrics.containerHeight == ViewportCanvasChromeLayout.viewportBadgeSize.height)
    #expect(WorkspaceChromeControlMetrics.containerHeight == 28.0)
}

@Test func workspaceChromeControlsUseSharedBorderlessLiquidGlassControlShape() {
    #expect(WorkspaceChromeControlMetrics.cornerRadius < ViewportCanvasChromeMetrics.cornerRadius)
    #expect(
        WorkspaceChromeControlMetrics.containerHorizontalPadding
            == ViewportCanvasChromeMetrics.topControlHorizontalPadding
    )
    #expect(
        WorkspaceChromeControlMetrics.itemSpacing
            == ViewportCanvasChromeMetrics.topControlItemSpacing
    )
    #expect(WorkspaceChromeControlMetrics.horizontalPadding == ViewportCanvasChromeMetrics.edgePadding)
    #expect(ViewportCanvasChromeMetrics.surfaceTintOpacity > 0.0)
    #expect(ViewportCanvasChromeMetrics.surfaceTintOpacity <= 0.03)
    #expect(ViewportCanvasChromeMetrics.borderWidth == 0.0)
    #expect(ViewportCanvasChromeMetrics.borderOpacity == 0.0)
}

@Test func workspaceChromeControlsStayContentSizedOnCanvas() {
    let viewportBadgeWidth = ViewportCanvasChromeLayout.defaultViewportBadgeWidth
    let topBarMinimumContentWidth = WorkspaceChromeControlMetrics.iconButtonSize.width * 3.0
        + WorkspaceChromeControlMetrics.itemSpacing * 2.0
        + WorkspaceChromeControlMetrics.containerHorizontalPadding * 2.0

    #expect(topBarMinimumContentWidth < viewportBadgeWidth)
    #expect(ViewportCanvasChromeLayout.defaultViewportBadgeWidth == ViewportCanvasChromeLayout.minimumViewportBadgeWidth)
    #expect(ViewportCanvasChromeLayout.viewportBadgeSize.width == ViewportCanvasChromeMetrics.topControlMaximumWidth)
}

@Test func workspaceTopBarPresentationStaysCanvasActionOnly() {
    let emptyPresentation = WorkspaceTopBarPresentation(selectedTargetCount: 0)
    let selectedPresentation = WorkspaceTopBarPresentation(selectedTargetCount: 2)
    let fieldNames = Mirror(reflecting: emptyPresentation).children.compactMap(\.label)

    #expect(emptyPresentation.selectionTitle == nil)
    #expect(selectedPresentation.selectionTitle == "2 selected")
    #expect(fieldNames == ["selectedTargetCount"])
    #expect(!fieldNames.contains { $0.localizedCaseInsensitiveContains("document") })
    #expect(!fieldNames.contains { $0.localizedCaseInsensitiveContains("title") })
    #expect(!fieldNames.contains { $0.localizedCaseInsensitiveContains("evaluation") })
    #expect(!fieldNames.contains { $0.localizedCaseInsensitiveContains("unit") })
}
