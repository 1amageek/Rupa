import RupaRendering
import Testing
@testable import RupaUI

@Test func workspaceSelectionScopeMapsToViewportSelectionHitPolicy() {
    #expect(WorkspaceSelectionScope.object.viewportSelectionHitPolicy == .object)
    #expect(WorkspaceSelectionScope.face.viewportSelectionHitPolicy == .face)
    #expect(WorkspaceSelectionScope.edge.viewportSelectionHitPolicy == .edge)
    #expect(WorkspaceSelectionScope.vertex.viewportSelectionHitPolicy == .vertex)
    #expect(WorkspaceSelectionScope.region.viewportSelectionHitPolicy == .region)
    #expect(WorkspaceSelectionScope.sketchEntity.viewportSelectionHitPolicy == .sketchEntity)
}

@Test func workspaceSelectionScopeAllowsRectangleSelectionForEverySelectableScope() {
    for scope in WorkspaceSelectionScope.allCases {
        #expect(scope.isEnabled)
        #expect(scope.allowsSelectionRectangle)
    }
}

@Test func workspaceSelectionScopeControlUsesCompactGridWithinUtilityRail() {
    #expect(WorkspaceSelectionScopeControlLayout.columnCount == 3)
    #expect(WorkspaceSelectionScopeControlLayout.rowCount(itemCount: WorkspaceSelectionScope.allCases.count) == 2)
    #expect(WorkspaceSelectionScopeControlLayout.contentWidth <= 162.0)
    #expect(WorkspaceSelectionScopeControlLayout.buttonSize.width >= 48.0)
}
