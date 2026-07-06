import RupaAutomation

extension CLIResponse {
    public init(
        result: AutomationResult,
        dirty: Bool,
        saved: Bool
    ) {
        self.init(
            message: result.message,
            generation: result.generation.value,
            dirty: dirty,
            saved: saved,
            primaryFeatureID: result.primaryFeatureID,
            createdFeatureIDs: result.createdFeatureIDs.isEmpty ? nil : result.createdFeatureIDs,
            diagnostics: result.diagnostics,
            workspaceScale: result.workspaceScale,
            workspaceInteractionScale: result.workspaceInteractionScale,
            workspaceBounds: result.workspaceBounds,
            workspacePrecision: result.workspacePrecision,
            workspaceScaleRecommendation: result.workspaceScaleRecommendation,
            workspaceScalePresetOptions: result.workspaceScalePresetOptions,
            viewportGridSettings: result.viewportGridSettings,
            viewportGridScale: result.viewportGridScale,
            savedViews: result.savedViews,
            savedViewID: result.savedViewID,
            drawingProjection: result.drawingProjection
        )
    }
}
