import CoreGraphics
import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceCanvasOverlayGeometryNormalizesHeight() {
    #expect(WorkspaceCanvasOverlayGeometry.normalizedHeight(42.2) == 43.0)
    #expect(WorkspaceCanvasOverlayGeometry.normalizedHeight(42.0) == 42.0)
    #expect(WorkspaceCanvasOverlayGeometry.normalizedHeight(-1.0) == 0.0)
}

@Test func workspaceCanvasOverlayGeometryNormalizesAndSortsExclusions() {
    let exclusions = WorkspaceCanvasOverlayGeometry.normalizedExclusions([
        .topBar: CGRect(x: 120.8, y: 12.2, width: 80.1, height: 26.4),
        .toolPalette: CGRect(x: 8.4, y: 12.2, width: 44.2, height: 210.5),
        .contextPanel: CGRect(x: 20.0, y: 520.2, width: 720.2, height: 39.1),
    ])

    #expect(exclusions.count == 3)
    #expect(exclusions[0].rect == CGRect(x: 8.0, y: 12.0, width: 45.0, height: 211.0))
    #expect(exclusions[0].fittingEdges == .leading)
    #expect(exclusions[1].rect == CGRect(x: 120.0, y: 12.0, width: 81.0, height: 27.0))
    #expect(exclusions[1].fittingEdges == .top)
    #expect(exclusions[2].rect == CGRect(x: 20.0, y: 520.0, width: 721.0, height: 40.0))
    #expect(exclusions[2].fittingEdges == .bottom)
}

@Test func workspaceCanvasOverlayGeometryDropsInvalidExclusions() {
    let exclusions = WorkspaceCanvasOverlayGeometry.normalizedExclusions([
        .topBar: CGRect(x: 16.0, y: 12.0, width: 120.0, height: 32.0),
        .toolPalette: CGRect(x: CGFloat.nan, y: 0.0, width: 44.0, height: 320.0),
        .utilityRail: CGRect(x: 700.0, y: 0.0, width: CGFloat.infinity, height: 320.0),
        .contextPanel: CGRect(x: 0.0, y: 560.0, width: 800.0, height: 0.0),
    ])

    #expect(exclusions == [
        ViewportCanvasOverlayExclusion(
            rect: CGRect(x: 16.0, y: 12.0, width: 120.0, height: 32.0),
            fittingEdges: .top
        ),
    ])
}
