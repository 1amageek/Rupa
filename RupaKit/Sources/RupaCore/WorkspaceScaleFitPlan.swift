import Foundation

public struct WorkspaceScaleFitPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case alreadyFits
        case applyPreset(WorkspaceScalePreset)
        case unsupportedRange
    }

    public var action: Action
    public var measurement: MeasurementResult
    public var recommendation: WorkspaceScaleRecommendation?

    public init(
        action: Action,
        measurement: MeasurementResult,
        recommendation: WorkspaceScaleRecommendation?
    ) {
        self.action = action
        self.measurement = measurement
        self.recommendation = recommendation
    }
}
