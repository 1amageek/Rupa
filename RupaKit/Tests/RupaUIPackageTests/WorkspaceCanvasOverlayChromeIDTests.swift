import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceCanvasOverlayChromeIDsDeclareViewportFittingEdges() {
    #expect(WorkspaceCanvasOverlayChromeID.allCases.count == 2)
    #expect(WorkspaceCanvasOverlayChromeID.toolPalette.fittingEdges == .leading)
    #expect(WorkspaceCanvasOverlayChromeID.contextPanel.fittingEdges == .bottom)
}
