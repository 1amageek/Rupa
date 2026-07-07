import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceCanvasOverlayChromeIDsDeclareViewportFittingEdges() {
    #expect(WorkspaceCanvasOverlayChromeID.topBar.fittingEdges == .top)
    #expect(WorkspaceCanvasOverlayChromeID.toolPalette.fittingEdges == .leading)
    #expect(WorkspaceCanvasOverlayChromeID.utilityRail.fittingEdges == .trailing)
    #expect(WorkspaceCanvasOverlayChromeID.contextPanel.fittingEdges == .bottom)
}
