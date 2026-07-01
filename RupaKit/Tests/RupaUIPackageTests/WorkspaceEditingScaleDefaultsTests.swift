import Testing
@testable import RupaCore
@testable import RupaUI

@Test func workspaceEditingDefaultsMatchMillimeterScale() {
    let defaults = WorkspaceEditingScaleDefaults(ruler: .standard(for: .millimeter))

    #expect(defaults.operationStepMeters == 0.001)
    #expect(defaults.slotWidthMeters == 0.002)
    #expect(abs(defaults.sketchRebuildToleranceMeters - 0.000_001) < 1.0e-12)
    #expect(defaults.sketchRebuildToleranceRange.upperBound == 0.01)
}

@Test func workspaceEditingDefaultsFollowSitePlanningScale() {
    let defaults = WorkspaceEditingScaleDefaults(ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    #expect(defaults.operationStepMeters == 100.0)
    #expect(defaults.slotWidthMeters == 200.0)
    #expect(abs(defaults.sketchRebuildToleranceMeters - 0.1) < 1.0e-12)
    #expect(defaults.sketchRebuildToleranceRange.upperBound == 100.0)
}

@Test func workspaceEditingDefaultsKeepRebuildToleranceSeparateFromGridStep() {
    let architecture = WorkspaceEditingScaleDefaults(ruler: WorkspaceScalePreset.architecture.rulerConfiguration)
    let site = WorkspaceEditingScaleDefaults(ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    #expect(architecture.operationStepMeters == 0.1)
    #expect(abs(architecture.sketchRebuildToleranceMeters - 0.002) < 1.0e-12)
    #expect(site.operationStepMeters == 100.0)
    #expect(site.sketchRebuildToleranceMeters < site.operationStepMeters * 0.01)
}
