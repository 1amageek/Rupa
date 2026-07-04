import Testing
@testable import RupaUI

@Test func workspaceTopBarPresentationHidesEmptySelectionCount() {
    let presentation = WorkspaceTopBarPresentation(selectedTargetCount: 0)

    #expect(!presentation.showsSelectionCount)
    #expect(presentation.selectionTitle == nil)
    #expect(Mirror(reflecting: presentation).children.contains { $0.label == "documentName" } == false)
    #expect(Mirror(reflecting: presentation).children.contains { $0.label == "documentTitle" } == false)
}

@Test func workspaceTopBarPresentationShowsPositiveSelectionCount() {
    let presentation = WorkspaceTopBarPresentation(selectedTargetCount: 3)

    #expect(presentation.showsSelectionCount)
    #expect(presentation.selectionTitle == "3 selected")
}

@Test func workspaceTopBarPresentationNormalizesNegativeSelectionCount() {
    let presentation = WorkspaceTopBarPresentation(selectedTargetCount: -1)

    #expect(presentation.selectedTargetCount == 0)
    #expect(!presentation.showsSelectionCount)
    #expect(presentation.selectionTitle == nil)
}
