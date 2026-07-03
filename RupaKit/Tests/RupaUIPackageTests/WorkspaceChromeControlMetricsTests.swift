import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceChromeControlsShareCompactCanvasHeight() {
    #expect(WorkspaceChromeControlMetrics.iconButtonSize.width == WorkspaceChromeControlMetrics.controlHeight)
    #expect(WorkspaceChromeControlMetrics.iconButtonSize.height == WorkspaceChromeControlMetrics.controlHeight)
    #expect(WorkspaceChromeControlMetrics.controlHeight <= ViewportCanvasChromeMetrics.topControlHeight - 8.0)
    #expect(WorkspaceChromeControlMetrics.dividerHeight <= WorkspaceChromeControlMetrics.controlHeight)
}

@Test func workspaceChromeControlsUseFillOnlyRegularControlShape() {
    #expect(WorkspaceChromeControlMetrics.cornerRadius < ViewportCanvasChromeMetrics.cornerRadius)
    #expect(WorkspaceChromeControlMetrics.horizontalPadding <= ViewportCanvasChromeMetrics.edgePadding)
}
