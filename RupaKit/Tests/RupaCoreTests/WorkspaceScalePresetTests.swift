import Foundation
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

    #expect(snapshot.visibleSpanDisplayValue == 100_000.0)
    #expect(snapshot.summary.contains("minor 10 m"))
    #expect(snapshot.summary.contains("major 100 m"))
    #expect(snapshot.summary.contains("visible span 100,000 m"))
}

@Test func workspaceScaleSnapshotExposesDisplayUnitValues() {
    let snapshot = WorkspaceScaleSnapshot(
        ruler: WorkspaceScalePreset.sitePlanningImperial.rulerConfiguration
    )

    #expect(snapshot.displayUnit == .foot)
    #expect(snapshot.minorTickMeters == 30.48)
    #expect(snapshot.minorTickDisplayValue == 100.0)
    #expect(snapshot.majorTickDisplayValue == 1_000.0)
    #expect(abs(snapshot.visibleSpanDisplayValue - 328_083.9895013123) < 1.0e-9)
    #expect(snapshot.summary.contains("minor 100 ft"))
    #expect(snapshot.summary.contains("major 1,000 ft"))
    #expect(snapshot.summary.contains("visible span 328,083.989501 ft"))
}

@Test func workspaceScaleSnapshotDecodesMissingDisplayValuesFromMeters() throws {
    let json = """
    {
      "displayUnit": "foot",
      "displayUnitSymbol": "ft",
      "minorTickMeters": 0.3048,
      "majorTickMeters": 3.048,
      "visibleSpanMeters": 3048.0,
      "matchedPreset": null,
      "matchedPresetTitle": null
    }
    """

    let snapshot = try JSONDecoder().decode(
        WorkspaceScaleSnapshot.self,
        from: try #require(json.data(using: .utf8))
    )

    #expect(snapshot.displayUnit == .foot)
    #expect(snapshot.minorTickDisplayValue == 1.0)
    #expect(snapshot.majorTickDisplayValue == 10.0)
    #expect(snapshot.visibleSpanDisplayValue == 10_000.0)
}

@Test func workspaceScaleSnapshotRoundTripsDisplayValues() throws {
    let snapshot = WorkspaceScaleSnapshot(
        ruler: WorkspaceScalePreset.sitePlanningImperial.rulerConfiguration
    )

    let decoded = try JSONDecoder().decode(
        WorkspaceScaleSnapshot.self,
        from: try JSONEncoder().encode(snapshot)
    )

    #expect(decoded == snapshot)
    #expect(decoded.minorTickDisplayValue == 100.0)
    #expect(decoded.majorTickDisplayValue == 1_000.0)
}
