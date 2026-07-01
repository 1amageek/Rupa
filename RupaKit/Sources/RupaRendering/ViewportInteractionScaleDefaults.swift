import RupaCore

struct ViewportInteractionScaleDefaults: Equatable, Sendable {
    var operationStepMeters: Double
    var slotWidthMeters: Double

    init(ruler: RulerConfiguration) {
        let normalized = ruler.normalizedForWorkspaceScale()
        let operationStep = max(
            normalized.minorTickMeters,
            RulerConfiguration.minorTickMetersRange.lowerBound
        )
        self.operationStepMeters = operationStep
        self.slotWidthMeters = operationStep * 2.0
    }
}
