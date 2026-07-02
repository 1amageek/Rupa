import Foundation

public struct WorkspaceInteractionScaleDefaults: Equatable, Sendable {
    public let operationStepMeters: Double
    public let slotWidthMeters: Double
    public let surfaceFrameTangentialMoveMeters: Double
    public let surfaceFrameNormalMoveMeters: Double
    public let sketchRebuildToleranceMeters: Double
    public let sketchRebuildToleranceRange: ClosedRange<Double>

    public init(ruler: RulerConfiguration) {
        let normalized = ruler.normalizedForWorkspaceScale()
        let step = max(
            normalized.minorTickMeters,
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        self.operationStepMeters = step
        self.slotWidthMeters = step * 2.0
        self.surfaceFrameTangentialMoveMeters = 0.0
        self.surfaceFrameNormalMoveMeters = step
        self.sketchRebuildToleranceMeters = Self.sketchRebuildToleranceMeters(
            ruler: normalized,
            operationStepMeters: step
        )
        self.sketchRebuildToleranceRange = RulerConfiguration.minorTickMetersRange.lowerBound
            ... max(step, 0.01)
    }

    private static func sketchRebuildToleranceMeters(
        ruler: RulerConfiguration,
        operationStepMeters: Double
    ) -> Double {
        let gridFraction = operationStepMeters * 0.1
        let visiblePrecisionBudget = ruler.visibleSpanMeters * 1.0e-6
        return max(
            min(gridFraction, visiblePrecisionBudget),
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
    }
}
