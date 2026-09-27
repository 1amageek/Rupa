import RupaCore
import Testing
@testable import RupaUI

@Test func workspaceViewportContextPanelHidesIdleSelectState() {
    #expect(!WorkspaceViewportContextPanelVisibility.isVisible(
        selectedTool: .select,
        selectedTargetCount: 0,
        selectedReferenceCount: 0,
        runningCommandInputs: []
    ))
}

@Test func workspaceViewportContextPanelShowsSelectedTargetsAndReferences() {
    #expect(WorkspaceViewportContextPanelVisibility.isVisible(
        selectedTool: .select,
        selectedTargetCount: 1,
        selectedReferenceCount: 0,
        runningCommandInputs: []
    ))
    #expect(WorkspaceViewportContextPanelVisibility.isVisible(
        selectedTool: .select,
        selectedTargetCount: 0,
        selectedReferenceCount: 1,
        runningCommandInputs: []
    ))
}

/// Every running command keeps the panel that holds its inputs with nothing selected, so Section
/// Analysis started from an empty selection shows its Plane, Distance and Flip.
@Test func workspaceViewportContextPanelShowsRunningCommandsWithNothingSelected() {
    for input in WorkspaceViewportContextPanelVisibility.CommandInput.allCases {
        #expect(WorkspaceViewportContextPanelVisibility.isVisible(
            selectedTool: .select,
            selectedTargetCount: 0,
            selectedReferenceCount: 0,
            runningCommandInputs: [input]
        ), "\(input)")
    }
}

@Test func workspaceViewportContextPanelShowsCreationTools() {
    for tool in ModelingTool.allCases where tool != .select {
        #expect(WorkspaceViewportContextPanelVisibility.isVisible(
            selectedTool: tool,
            selectedTargetCount: 0,
            selectedReferenceCount: 0,
            runningCommandInputs: []
        ))
    }
}

@Test func workspaceViewportContextPanelPresentsIdleSelectionState() {
    #expect(WorkspaceViewportContextPanelVisibility.selectionPresentation(
        selectedSceneNodeCount: 0,
        selectedTargetCount: 0,
        selectedReferenceCount: 0
    ) == .idle)
}

@Test func workspaceViewportContextPanelPresentsTargetSelectionState() {
    #expect(WorkspaceViewportContextPanelVisibility.selectionPresentation(
        selectedSceneNodeCount: 1,
        selectedTargetCount: 0,
        selectedReferenceCount: 0
    ) == .targetSelection)
    #expect(WorkspaceViewportContextPanelVisibility.selectionPresentation(
        selectedSceneNodeCount: 0,
        selectedTargetCount: 1,
        selectedReferenceCount: 0
    ) == .targetSelection)
}

@Test func workspaceViewportContextPanelPresentsReferenceSelectionState() {
    #expect(WorkspaceViewportContextPanelVisibility.selectionPresentation(
        selectedSceneNodeCount: 0,
        selectedTargetCount: 0,
        selectedReferenceCount: 1
    ) == .referenceSelection)
}

@Test func workspaceViewportContextPanelPrefersTargetSelectionState() {
    #expect(WorkspaceViewportContextPanelVisibility.selectionPresentation(
        selectedSceneNodeCount: 1,
        selectedTargetCount: 1,
        selectedReferenceCount: 1
    ) == .targetSelection)
}
