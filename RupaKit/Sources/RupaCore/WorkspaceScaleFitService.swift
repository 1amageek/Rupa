import Foundation

public struct WorkspaceScaleFitService: Sendable {
    public init() {}

    public func plan(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> WorkspaceScaleFitPlan {
        let measurement = try MeasurementService(
            tolerance: .workspaceScaleAware(for: document)
        ).measure(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )

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
