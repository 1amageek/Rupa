import RupaCore

struct WorkspaceScaleFitPromptState: Equatable, Sendable {
    var title: String
    var accessibilityValue: String
    var help: String
    var isActionable: Bool
    var preset: WorkspaceScalePreset

    init?(recommendation: WorkspaceScaleRecommendation?) {
        guard let recommendation else {
            return nil
        }
        self.preset = recommendation.recommendedPreset
        self.isActionable = recommendation.isActionable
        self.title = Self.title(
            for: recommendation.recommendedPreset,
            isActionable: recommendation.isActionable
        )
        self.accessibilityValue = [
            recommendation.reason.rawValue,
            recommendation.recommendedScaleProfile.title,
            recommendation.recommendedScaleProfile.comfortableModelSpanTitle,
        ].joined(separator: ", ")
        self.help = recommendation.isActionable
            ? "Fit workspace scale to \(recommendation.recommendedScaleProfile.title)"
            : "Current model exceeds the supported workspace scale range"
    }

    private static func title(
        for preset: WorkspaceScalePreset,
        isActionable: Bool
    ) -> String {
        guard isActionable else {
            return "Scale Limit"
        }
        return "Fit \(preset.compactWorkspaceTitle)"
    }
}
