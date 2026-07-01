import Testing
@testable import RupaCore

@Test func workspaceScalePresetsProduceValidRulerConfigurations() throws {
    for preset in WorkspaceScalePreset.allCases {
        let configuration = preset.rulerConfiguration.normalizedForWorkspaceScale()

        try configuration.validate()
        #expect(WorkspaceScalePreset.matching(configuration) == preset)
    }
}

@Test func workspaceScalePresetsCoverPrecisionThroughSitePlanning() {
    let micro = WorkspaceScalePreset.microFabrication.rulerConfiguration
    let precision = WorkspaceScalePreset.precisionMechanical.rulerConfiguration
    let architecture = WorkspaceScalePreset.architecture.rulerConfiguration
    let architectureImperial = WorkspaceScalePreset.architectureImperial.rulerConfiguration
    let site = WorkspaceScalePreset.sitePlanning.rulerConfiguration
    let siteImperial = WorkspaceScalePreset.sitePlanningImperial.rulerConfiguration

    #expect(micro.displayUnit == .micrometer)
    #expect(precision.displayUnit == .millimeter)
    #expect(architecture.displayUnit == .meter)
    #expect(architectureImperial.displayUnit == .foot)
    #expect(site.displayUnit == .meter)
    #expect(siteImperial.displayUnit == .foot)
    #expect(micro.visibleSpanMeters < precision.visibleSpanMeters)
    #expect(precision.visibleSpanMeters < architecture.visibleSpanMeters)
    #expect(site.visibleSpanMeters == RulerConfiguration.visibleSpanMetersRange.upperBound)
    #expect(siteImperial.visibleSpanMeters == RulerConfiguration.visibleSpanMetersRange.upperBound)
}

@Test func workspaceScaleDefaultsFollowSitePlanningPreset() {
    let defaults = WorkspaceScaleDefaults(ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    #expect(defaults.placedSolidSideMeters == 4_000.0)
    #expect(defaults.sketchDepthMeters == 1_000.0)
}

@Test func workspaceScaleSnapshotSummaryGroupsLargeMeterValues() {
    let snapshot = WorkspaceScaleSnapshot(ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    #expect(snapshot.summary.contains("minor 10 m"))
    #expect(snapshot.summary.contains("major 100 m"))
    #expect(snapshot.summary.contains("visible span 100,000 m"))
}
