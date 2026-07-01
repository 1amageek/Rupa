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

@Test func workspaceSelectionScopeControlFitsUtilityRailAsSingleIconRow() {
    #expect(WorkspaceSelectionScopeControlLayout.columnCount == WorkspaceSelectionScope.allCases.count)
    #expect(WorkspaceSelectionScopeControlLayout.rowCount(itemCount: WorkspaceSelectionScope.allCases.count) == 1)
    #expect(WorkspaceSelectionScopeControlLayout.fitsInUtilityRail)
    #expect(WorkspaceSelectionScopeControlLayout.contentWidth <= WorkspaceUtilityRailLayout.contentWidth)
    #expect(WorkspaceSelectionScopeControlLayout.buttonSize.width >= 25.0)
    #expect(WorkspaceSelectionScopeControlLayout.buttonSize.height == 26.0)
    #expect(WorkspaceUtilityRailLayout.contentWidth == 162.0)
}
