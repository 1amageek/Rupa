import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceChromeControlsShareCompactCanvasHeight() {
    #expect(WorkspaceChromeControlMetrics.iconButtonSize.width == WorkspaceChromeControlMetrics.controlHeight)
    #expect(WorkspaceChromeControlMetrics.iconButtonSize.height == WorkspaceChromeControlMetrics.controlHeight)
    #expect(WorkspaceChromeControlMetrics.controlHeight <= ViewportCanvasChromeMetrics.topControlHeight - 8.0)
    #expect(WorkspaceChromeControlMetrics.dividerHeight <= WorkspaceChromeControlMetrics.controlHeight)
    let containedHeight = WorkspaceChromeControlMetrics.controlHeight
        + WorkspaceChromeControlMetrics.containerVerticalPadding * 2.0
    #expect(abs(containedHeight - ViewportCanvasChromeMetrics.topControlHeight) < 1.0e-9)
}

@Test func workspaceChromeControlsUseFillOnlyRegularControlShape() {
    #expect(WorkspaceChromeControlMetrics.cornerRadius < ViewportCanvasChromeMetrics.cornerRadius)
    #expect(WorkspaceChromeControlMetrics.horizontalPadding <= ViewportCanvasChromeMetrics.edgePadding)
}
