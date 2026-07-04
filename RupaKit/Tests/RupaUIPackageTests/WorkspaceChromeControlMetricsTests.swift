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
    #expect(ViewportCanvasChromeMetrics.topControlHeight == 30.0)
    #expect(ViewportCanvasChromeMetrics.topControlContentHeight == 22.0)
    #expect(ViewportCanvasChromeMetrics.edgePadding == 6.0)
    #expect(ViewportCanvasChromeMetrics.topControlItemSpacing == ViewportCanvasChromeMetrics.edgePadding)
    #expect(ViewportCanvasChromeMetrics.topControlMaximumWidth == 190.0)
    #expect(WorkspaceChromeControlMetrics.containerHeight == ViewportCanvasChromeLayout.viewportBadgeSize.height)
    #expect(WorkspaceChromeControlMetrics.containerHeight == 30.0)
}

@Test func workspaceChromeControlsUseSharedLiquidGlassControlShape() {
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
    #expect(ViewportCanvasChromeMetrics.outlineWidth > 0.0)
    #expect(ViewportCanvasChromeMetrics.outlineWidth <= 1.0)
    #expect(ViewportCanvasChromeMetrics.outlineOpacity > 0.0)
    #expect(ViewportCanvasChromeMetrics.outlineOpacity >= 0.22)
    #expect(ViewportCanvasChromeMetrics.outlineOpacity <= 0.24)
}

@Test func workspaceChromeControlsStayContentSizedOnCanvas() {
    let viewportBadgeWidth = ViewportCanvasChromeLayout.defaultViewportBadgeWidth
    let topBarMinimumContentWidth = WorkspaceChromeControlMetrics.iconButtonSize.width * 3.0
        + WorkspaceChromeControlMetrics.itemSpacing * 2.0
        + WorkspaceChromeControlMetrics.containerHorizontalPadding * 2.0

    #expect(topBarMinimumContentWidth < viewportBadgeWidth)
    #expect(ViewportCanvasChromeLayout.viewportBadgeSize.width == ViewportCanvasChromeMetrics.topControlMaximumWidth)
}
