import RupaCore

enum WorkspaceViewportContextPanelVisibility {
    enum SelectionPresentation: Equatable {
        case idle
        case targetSelection
        case referenceSelection
    }

    static func isVisible(
        selectedTool: ModelingTool,
        selectedTargetCount: Int,
        selectedReferenceCount: Int,
        isDimensionCommandActive: Bool,
        hasViewAlignedConstructionPlaneRequest: Bool
    ) -> Bool {
        if hasViewAlignedConstructionPlaneRequest {
            return true
        }
        if isDimensionCommandActive {
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
