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
    #expect(WorkspaceSelectionScopeControlLayout.columnCount == 6)
    #expect(WorkspaceSelectionScopeControlLayout.rowCount(itemCount: WorkspaceSelectionScope.allCases.count) == 1)
    #expect(WorkspaceSelectionScopeControlLayout.contentWidth <= 162.0)
    #expect(WorkspaceSelectionScopeControlLayout.buttonSize.width >= 25.0)
    #expect(WorkspaceSelectionScopeControlLayout.buttonSize.height >= 28.0)
}
