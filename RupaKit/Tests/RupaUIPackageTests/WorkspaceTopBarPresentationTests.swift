import Testing
@testable import RupaUI

@Test func workspaceTopBarPresentationHidesEmptySelectionCount() {
    let presentation = WorkspaceTopBarPresentation(
        selectedTargetCount: 0,
        selectionScope: .object
    )

    #expect(!presentation.showsSelectionCount)
    #expect(presentation.selectionTitle == nil)
    #expect(Mirror(reflecting: presentation).children.contains { $0.label == "documentName" } == false)
    #expect(Mirror(reflecting: presentation).children.contains { $0.label == "documentTitle" } == false)
}

@Test func workspaceTopBarPresentationShowsPositiveSelectionCount() {
    let presentation = WorkspaceTopBarPresentation(
        selectedTargetCount: 3,
        selectionScope: .object
    )

    #expect(presentation.showsSelectionCount)
    #expect(presentation.selectionTitle == "3 selected")
}

@Test func workspaceTopBarPresentationNormalizesNegativeSelectionCount() {
    let presentation = WorkspaceTopBarPresentation(
        selectedTargetCount: -1,
        selectionScope: .object
    )

    #expect(presentation.selectedTargetCount == 0)
    #expect(!presentation.showsSelectionCount)
    #expect(presentation.selectionTitle == nil)
}

@Test func workspaceTopBarPresentationNamesTheSelectionScope() {
    // A scope changed by digit key never touches the rail, so the top bar is
    // where it becomes visible.
    for scope in WorkspaceSelectionScope.allCases {
        let presentation = WorkspaceTopBarPresentation(
            selectedTargetCount: 1,
            selectionScope: scope
        )

        #expect(presentation.selectionScopeTitle == scope.title)
        #expect(presentation.selectionScopeSystemImage == scope.systemImage)
    }
}

@Test func workspaceTopBarPresentationNamesTheScopeWithoutASelection() {
    let presentation = WorkspaceTopBarPresentation(
        selectedTargetCount: 0,
        selectionScope: .edge
    )

    #expect(presentation.selectionTitle == nil)
    #expect(presentation.selectionScopeTitle == "Edge")
}
