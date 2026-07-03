import RupaRendering
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
}

@Test func workspaceChromeControlsUseFillOnlyRegularControlShape() {
    #expect(WorkspaceChromeControlMetrics.cornerRadius < ViewportCanvasChromeMetrics.cornerRadius)
    #expect(
        WorkspaceChromeControlMetrics.containerHorizontalPadding
            == ViewportCanvasChromeMetrics.topControlHorizontalPadding
    )
    #expect(
        WorkspaceChromeControlMetrics.itemSpacing
            == ViewportCanvasChromeMetrics.topControlItemSpacing
    )
    #expect(WorkspaceChromeControlMetrics.horizontalPadding <= ViewportCanvasChromeMetrics.edgePadding)
}
