import RupaCore

struct WorkspaceEditingScaleDefaults: Equatable, Sendable {
    var operationStepMeters: Double
    var slotWidthMeters: Double
    var sketchRebuildToleranceMeters: Double
    var sketchRebuildToleranceRange: ClosedRange<Double>

    init(ruler: RulerConfiguration) {
        let normalized = ruler.normalizedForWorkspaceScale()
        let step = max(
            normalized.minorTickMeters,
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        self.operationStepMeters = step
        self.slotWidthMeters = step * 2.0
        self.sketchRebuildToleranceMeters = max(
            step * 0.1,
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        self.sketchRebuildToleranceRange = RulerConfiguration.minorTickMetersRange.lowerBound
            ... max(step, 0.01)
    }
}
