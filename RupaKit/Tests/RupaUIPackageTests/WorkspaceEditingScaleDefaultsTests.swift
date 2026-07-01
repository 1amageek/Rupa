import Testing
@testable import RupaCore
@testable import RupaUI

@Test func workspaceEditingDefaultsMatchMillimeterScale() {
    let defaults = WorkspaceEditingScaleDefaults(ruler: .standard(for: .millimeter))

    #expect(defaults.operationStepMeters == 0.001)
    #expect(defaults.slotWidthMeters == 0.002)
    #expect(defaults.sketchRebuildToleranceMeters == 0.0001)
    #expect(defaults.sketchRebuildToleranceRange.upperBound == 0.01)
}

@Test func workspaceEditingDefaultsFollowSitePlanningScale() {
    let defaults = WorkspaceEditingScaleDefaults(ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    #expect(defaults.operationStepMeters == 10.0)
    #expect(defaults.slotWidthMeters == 20.0)
    #expect(defaults.sketchRebuildToleranceMeters == 1.0)
    #expect(defaults.sketchRebuildToleranceRange.upperBound == 10.0)
}
