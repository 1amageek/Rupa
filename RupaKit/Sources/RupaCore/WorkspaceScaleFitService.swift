import Foundation

public struct WorkspaceScaleFitService: Sendable {
    public init() {}

    public func plan(
        document: DesignDocument,
        ruler: RulerConfiguration,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> WorkspaceScaleFitPlan {
        let measurement = try MeasurementService(
            tolerance: document.modelingSettings.tolerance
        ).measure(
            document: document,
            ruler: ruler,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )

        return plan(measurement: measurement)
    }

    public func plan(
        bounds: MeasurementResult.Bounds?,
        ruler: RulerConfiguration
    ) -> WorkspaceScaleFitPlan {
        let recommendation = WorkspaceScaleRecommendationService().recommendation(
            for: bounds,
            currentRuler: ruler
        )
        return plan(
            measurement: MeasurementResult(
                displayUnit: ruler.displayUnit,
                bounds: bounds,
                workspaceScaleRecommendation: recommendation
            )
        )
    }

    private func plan(measurement: MeasurementResult) -> WorkspaceScaleFitPlan {
        guard let recommendation = measurement.workspaceScaleRecommendation else {
            return WorkspaceScaleFitPlan(
                action: .alreadyFits,
                measurement: measurement,
                recommendation: nil
            )
        }

        guard recommendation.isActionable else {
            return WorkspaceScaleFitPlan(
                action: .unsupportedRange,
                measurement: measurement,
                recommendation: recommendation
            )
        }

        return WorkspaceScaleFitPlan(
            action: .applyPreset(recommendation.recommendedPreset),
            measurement: measurement,
            recommendation: recommendation
        )
    }
}
