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
    #expect(ViewportCanvasChromeMetrics.topControlHeight == 26.0)
    #expect(ViewportCanvasChromeMetrics.topControlContentHeight == 18.0)
    #expect(ViewportCanvasChromeMetrics.edgePadding == 4.0)
    #expect(ViewportCanvasChromeMetrics.topControlItemSpacing == ViewportCanvasChromeMetrics.edgePadding)
    #expect(WorkspaceChromeControlMetrics.containerHeight == 26.0)
}

/// A status sentence sits in the window toolbar beside the document title and the commands, so the
/// width it may take is declared rather than left to the sentence. It has to be wide enough to read
/// as a sentence rather than as one more chip, and narrow enough to leave the toolbar its own
/// controls: at the narrowest the window is laid out at, the sentence takes no more than a third
/// of the bar.
@Test func workspaceStatusMessageDeclaresTheWidthASentenceMayTake() {
    #expect(WorkspaceChromeControlMetrics.statusMessageMaximumWidth == 360.0)
    #expect(
        WorkspaceChromeControlMetrics.statusMessageMaximumWidth
            > WorkspaceSelectionScopeControlLayout.contentWidth
    )
    #expect(
        WorkspaceChromeControlMetrics.statusMessageMaximumWidth * 3.0
            <= WorkspaceEditorSplitLayout.minimumWindowWidth
    )
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

@Test func workspaceTopBarPresentationStaysCanvasActionOnly() {
    let emptyPresentation = WorkspaceTopBarPresentation(
        selectedTargetCount: 0,
        selectionScope: .object
    )
    let selectedPresentation = WorkspaceTopBarPresentation(
        selectedTargetCount: 2,
        selectionScope: .object
    )
    let fieldNames = Mirror(reflecting: emptyPresentation).children.compactMap(\.label)

    #expect(emptyPresentation.selectionTitle == nil)
    #expect(selectedPresentation.selectionTitle == "2 selected")
    #expect(fieldNames == ["selectedTargetCount", "selectionScope"])
    #expect(!fieldNames.contains { $0.localizedCaseInsensitiveContains("document") })
    #expect(!fieldNames.contains { $0.localizedCaseInsensitiveContains("title") })
    #expect(!fieldNames.contains { $0.localizedCaseInsensitiveContains("evaluation") })
    #expect(!fieldNames.contains { $0.localizedCaseInsensitiveContains("unit") })
}
