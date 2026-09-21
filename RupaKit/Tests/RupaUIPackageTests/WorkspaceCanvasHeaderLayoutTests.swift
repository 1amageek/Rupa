import CoreGraphics
import RupaRendering
import Testing
@testable import RupaUI

/// The header stands inside the canvas column rather than floating over the
/// canvas, so its fixed seats are a correctness bound: a row wider than the
/// column's declared minimum would be clipped at the narrowest width the
/// workspace is ever laid out at, and a clipped seat has no second copy
/// anywhere else to reach.
@Test func workspaceCanvasHeaderFixedSeatsFitTheNarrowestCanvasColumn() {
    #expect(WorkspaceCanvasHeaderLayout.fixedSeatsWidth == 580.0)
    #expect(
        WorkspaceCanvasHeaderLayout.fixedSeatsWidth
            <= WorkspaceEditorSplitLayout.minimumCanvasWidth
    )
}

@Test func workspaceCanvasHeaderSeatsDeclareTheWidthsTheBudgetCounts() {
    #expect(WorkspaceSelectionScopeControlLayout.contentWidth == 160.0)
    #expect(WorkspaceSnapControlLayout.contentWidth == 106.0)
    #expect(WorkspacePlaneModeControlLayout.contentWidth == 130.0)
    #expect(WorkspaceCanvasHeaderLayout.viewGroupWidth == 83.0)
    let seats = WorkspaceSelectionScopeControlLayout.contentWidth
        + WorkspaceSnapControlLayout.contentWidth
        + WorkspacePlaneModeControlLayout.contentWidth
        + WorkspaceCanvasHeaderLayout.viewGroupWidth
        + WorkspaceCanvasHeaderLayout.controlSize.width * 2.0
    #expect(seats == 529.0)
}

/// The bar's height is declared, not measured. The readouts on its trailing
/// end come and go, and a height that followed them would move the canvas
/// under the pointer every time one arrived.
@Test func workspaceCanvasHeaderDeclaresItsHeight() {
    #expect(WorkspaceCanvasHeaderLayout.height == 34.0)
    #expect(WorkspaceCanvasHeaderLayout.controlSize.height == WorkspaceChromeControlMetrics.containerHeight)
    #expect(WorkspaceCanvasHeaderLayout.dividerHeight <= WorkspaceCanvasHeaderLayout.controlSize.height)
}

/// The window cannot be narrower than the three columns it holds. The split
/// pane's own minimum only constrains a divider drag, so a window that allowed
/// less would squeeze the canvas column past the bound the header depends on.
@Test func workspaceEditorWindowIsNeverNarrowerThanItsThreeColumns() {
    #expect(WorkspaceEditorSplitLayout.minimumWindowWidth == 1_140.0)
    #expect(
        WorkspaceEditorSplitLayout.minimumWindowWidth
            >= WorkspaceEditorSplitLayout.sidebarMinimumWidth
            + WorkspaceCanvasHeaderLayout.fixedSeatsWidth
            + WorkspaceEditorSplitLayout.inspectorWidth
    )
}
