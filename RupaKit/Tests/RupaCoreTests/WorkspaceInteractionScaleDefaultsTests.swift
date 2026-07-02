import Testing
@testable import RupaCore

@Test func workspaceInteractionScaleDefaultsMatchMillimeterWorkspace() {
    let defaults = WorkspaceInteractionScaleDefaults(ruler: .standard(for: .millimeter))

    #expect(defaults.operationStepMeters == 0.001)
    #expect(defaults.slotWidthMeters == 0.002)
    #expect(defaults.surfaceFrameTangentialMoveMeters == 0.0)
    #expect(defaults.surfaceFrameNormalMoveMeters == defaults.operationStepMeters)
    #expect(abs(defaults.sketchRebuildToleranceMeters - 0.000_001) < 1.0e-12)
    #expect(defaults.sketchRebuildToleranceRange.upperBound == 0.01)
}

@Test func workspaceInteractionScaleDefaultsTrackArchitectureWorkspace() {
    let defaults = WorkspaceInteractionScaleDefaults(
        ruler: WorkspaceScalePreset.architecture.rulerConfiguration
    )

    #expect(defaults.operationStepMeters == 0.1)
    #expect(defaults.slotWidthMeters == 0.2)
    #expect(defaults.surfaceFrameTangentialMoveMeters == 0.0)
    #expect(defaults.surfaceFrameNormalMoveMeters == 0.1)
    #expect(abs(defaults.sketchRebuildToleranceMeters - 0.002) < 1.0e-12)
    #expect(defaults.sketchRebuildToleranceRange.upperBound == 0.1)
}

@Test func workspaceInteractionScaleDefaultsFollowSitePlanningWorkspace() {
    let defaults = WorkspaceInteractionScaleDefaults(
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )

    #expect(defaults.operationStepMeters == 100.0)
    #expect(defaults.slotWidthMeters == 200.0)
    #expect(defaults.surfaceFrameTangentialMoveMeters == 0.0)
    #expect(defaults.surfaceFrameNormalMoveMeters == 100.0)
    #expect(abs(defaults.sketchRebuildToleranceMeters - 0.1) < 1.0e-12)
    #expect(defaults.sketchRebuildToleranceRange.upperBound == 100.0)
}

@Test func workspaceInteractionScaleSnapshotUsesReadableKilometersForLargeMeterWorkspace() {
    let ruler = RulerConfiguration(
        displayUnit: .meter,
        minorTickMeters: 1_000.0,
        majorTickMeters: 10_000.0,
        visibleSpanMeters: 100_000.0
    )
    let snapshot = WorkspaceInteractionScaleSnapshot(ruler: ruler)

    #expect(snapshot.displayUnit == .meter)
    #expect(snapshot.displayUnitSymbol == "m")
    #expect(snapshot.operationStep.meters == 1_000.0)
    #expect(snapshot.operationStep.displayValue == 1.0)
    #expect(snapshot.operationStep.displayUnit == .kilometer)
    #expect(snapshot.operationStep.displayUnitSymbol == "km")
    #expect(snapshot.slotWidth.meters == 2_000.0)
    #expect(snapshot.slotWidth.displayValue == 2.0)
    #expect(snapshot.slotWidth.displayUnit == .kilometer)
}

@Test func workspaceInteractionScaleDefaultsKeepRebuildToleranceSeparateFromGridStep() {
    let architecture = WorkspaceInteractionScaleDefaults(
        ruler: WorkspaceScalePreset.architecture.rulerConfiguration
    )
    let site = WorkspaceInteractionScaleDefaults(
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )

    #expect(architecture.operationStepMeters == 0.1)
    #expect(abs(architecture.sketchRebuildToleranceMeters - 0.002) < 1.0e-12)
    #expect(site.operationStepMeters == 100.0)
    #expect(site.sketchRebuildToleranceMeters < site.operationStepMeters * 0.01)
}
