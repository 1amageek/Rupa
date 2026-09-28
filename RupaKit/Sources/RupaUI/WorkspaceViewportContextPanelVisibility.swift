import RupaCore

enum WorkspaceViewportContextPanelVisibility {
    enum SelectionPresentation: Equatable {
        case idle
        case targetSelection
        case referenceSelection
    }

    /// A running command whose inputs live in the panel. While one runs the panel stays, whatever
    /// is selected: Section Analysis starts with nothing selected, and D can only move focus into a
    /// field that exists.
    enum CommandInput: Hashable, CaseIterable {
        case viewAlignedConstructionPlane
        case dimension
        case place
        case transform
        case mirror
        case sectionAnalysis
        case cutCurve
        case fillet
        case rebuild
        case deform
        case project
    }

    static func isVisible(
        selectedTool: ModelingTool,
        selectedTargetCount: Int,
        selectedReferenceCount: Int,
        runningCommandInputs: Set<CommandInput>
    ) -> Bool {
        if !runningCommandInputs.isEmpty {
            return true
        }
        if selectedTargetCount > 0 || selectedReferenceCount > 0 {
            return true
        }
        return selectedTool != .select
    }

    static func selectionPresentation(
        selectedSceneNodeCount: Int,
        selectedTargetCount: Int,
        selectedReferenceCount: Int
    ) -> SelectionPresentation {
        if selectedSceneNodeCount > 0 || selectedTargetCount > 0 {
            return .targetSelection
        }
        if selectedReferenceCount > 0 {
            return .referenceSelection
        }
        return .idle
    }
}
