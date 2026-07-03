import RupaCore

enum WorkspaceViewportContextPanelVisibility {
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
}
