import CoreGraphics
import RupaCore
import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceToolPaletteUsesCompactCanvasMetrics() {
    #expect(WorkspaceToolPaletteMetrics.buttonSize >= ViewportCanvasChromeMetrics.topControlHeight)
    #expect(WorkspaceToolPaletteMetrics.buttonSize <= 32.0)
    #expect(WorkspaceToolPaletteMetrics.containerPadding <= ViewportCanvasChromeMetrics.edgePadding / 2.0)
    #expect(WorkspaceToolPaletteMetrics.itemSpacing <= WorkspaceChromeControlMetrics.containerVerticalPadding)
}

@Test func workspaceToolPaletteHeightScalesFromToolCount() {
    let toolCount = ModelingTool.allCases.count
    let expectedHeight = WorkspaceToolPaletteMetrics.containerPadding * 2.0
        + WorkspaceToolPaletteMetrics.buttonSize * CGFloat(toolCount)
        + WorkspaceToolPaletteMetrics.itemSpacing * CGFloat(toolCount - 1)
    let legacyHeight = 4.0 * 2.0 + 36.0 * CGFloat(toolCount) + 5.0 * CGFloat(toolCount - 1)

    #expect(WorkspaceToolPaletteMetrics.defaultHeight == expectedHeight)
    #expect(WorkspaceToolPaletteMetrics.defaultHeight < legacyHeight)
}
