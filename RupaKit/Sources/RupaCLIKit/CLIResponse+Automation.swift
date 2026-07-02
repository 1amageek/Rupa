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
            diagnostics: result.diagnostics,
            workspaceScale: result.workspaceScale,
            workspaceBounds: result.workspaceBounds,
            workspacePrecision: result.workspacePrecision,
            workspaceScaleRecommendation: result.workspaceScaleRecommendation,
            viewportGridSettings: result.viewportGridSettings
        )
    }
}
