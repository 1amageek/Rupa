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

@Test func workspaceScalePresetsCoverPrecisionThroughRegionalPlanning() {
    let micro = WorkspaceScalePreset.microFabrication.rulerConfiguration
    let precision = WorkspaceScalePreset.precisionMechanical.rulerConfiguration
    let architecture = WorkspaceScalePreset.architecture.rulerConfiguration
    let architectureImperial = WorkspaceScalePreset.architectureImperial.rulerConfiguration
    let urban = WorkspaceScalePreset.urbanPlanning.rulerConfiguration
    let site = WorkspaceScalePreset.sitePlanning.rulerConfiguration
    let regional = WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    let siteImperial = WorkspaceScalePreset.sitePlanningImperial.rulerConfiguration

    #expect(micro.displayUnit == .micrometer)
    #expect(precision.displayUnit == .millimeter)
    #expect(architecture.displayUnit == .meter)
    #expect(architectureImperial.displayUnit == .foot)
    #expect(urban.displayUnit == .kilometer)
    #expect(site.displayUnit == .kilometer)
    #expect(regional.displayUnit == .kilometer)
    #expect(siteImperial.displayUnit == .foot)
    #expect(micro.visibleSpanMeters < precision.visibleSpanMeters)
    #expect(precision.visibleSpanMeters < architecture.visibleSpanMeters)
    #expect(architecture.visibleSpanMeters < urban.visibleSpanMeters)
    #expect(urban.visibleSpanMeters < site.visibleSpanMeters)
    #expect(site.visibleSpanMeters < regional.visibleSpanMeters)
    #expect(urban.visibleSpanMeters == 25_000.0)
    #expect(site.visibleSpanMeters == 100_000.0)
    #expect(regional.visibleSpanMeters == 1_000_000.0)
    #expect(siteImperial.visibleSpanMeters == 100_000.0)
}

@Test func workspaceScalePresetsOrderMetricLadderBeforeImperialPresets() {
    #expect(WorkspaceScalePreset.allCases == [
        .microFabrication,
        .precisionMechanical,
        .productDesign,
        .roomInterior,
        .architecture,
        .urbanPlanning,
        .sitePlanning,
        .regionalPlanning,
        .architectureImperial,
        .sitePlanningImperial,
    ])
}

@Test func workspaceScalePresetProfilesExposeAllPresetsInCaseOrder() {
    #expect(WorkspaceScalePreset.profiles.map(\.preset) == WorkspaceScalePreset.allCases)
    #expect(WorkspaceScalePreset.profiles.contains { profile in
        profile.preset == .regionalPlanning
            && profile.visibleSpanTitle == "1,000 km"
            && profile.comfortableModelSpanTitle == "10 km to 800 km"
    })
    #expect(WorkspaceScalePreset.profiles.contains { profile in
        profile.preset == .urbanPlanning
            && profile.visibleSpanTitle == "25 km"
            && profile.comfortableModelSpanTitle == "0.25 km to 20 km"
    })
}

@Test func workspaceScaleDefaultsFollowSitePlanningPreset() {
    let defaults = WorkspaceScaleDefaults(ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    #expect(defaults.placedSolidSideMeters == 4_000.0)
    #expect(defaults.sketchDepthMeters == 1_000.0)
}

@Test func workspaceScaleSnapshotSummaryUsesKilometersForSitePlanning() {
    let snapshot = WorkspaceScaleSnapshot(ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration)

    #expect(snapshot.displayUnit == .kilometer)
    #expect(snapshot.displayUnitSymbol == "km")
    #expect(snapshot.minorTickDisplayValue == 0.1)
    #expect(snapshot.majorTickDisplayValue == 1.0)
    #expect(snapshot.visibleSpanDisplayValue == 100.0)
    #expect(snapshot.summary.contains("minor 0.1 km"))
    #expect(snapshot.summary.contains("major 1 km"))
    #expect(snapshot.summary.contains("visible span 100 km"))
}

@Test func workspaceScaleSnapshotSummaryUsesKilometersForUrbanPlanning() {
    let snapshot = WorkspaceScaleSnapshot(ruler: WorkspaceScalePreset.urbanPlanning.rulerConfiguration)

    #expect(snapshot.displayUnit == .kilometer)
    #expect(snapshot.displayUnitSymbol == "km")
    #expect(snapshot.minorTickDisplayValue == 0.01)
    #expect(snapshot.majorTickDisplayValue == 0.1)
    #expect(snapshot.visibleSpanDisplayValue == 25.0)
    #expect(snapshot.summary.contains("minor 0.01 km"))
    #expect(snapshot.summary.contains("major 0.1 km"))
    #expect(snapshot.summary.contains("visible span 25 km"))
}

@Test func workspaceScaleSnapshotSummaryUsesKilometersForRegionalPlanning() {
    let snapshot = WorkspaceScaleSnapshot(ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration)

    #expect(snapshot.displayUnit == .kilometer)
    #expect(snapshot.displayUnitSymbol == "km")
    #expect(snapshot.minorTickDisplayValue == 1.0)
    #expect(snapshot.majorTickDisplayValue == 10.0)
    #expect(snapshot.visibleSpanDisplayValue == 1_000.0)
    #expect(snapshot.summary.contains("minor 1 km"))
    #expect(snapshot.summary.contains("major 10 km"))
    #expect(snapshot.summary.contains("visible span 1,000 km"))
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

@Test func dimensionSummaryResultsDecodeMissingDisplayValues() throws {
    let objectTarget = SelectionTarget(sceneNodeID: SceneNodeID())
    let objectSummary = ObjectDimensionSummaryResult(
        displayUnit: .centimeter,
        entries: [
            ObjectDimensionSummaryResult.Entry(
                target: objectTarget,
                sceneNodeID: objectTarget.sceneNodeID.description,
                sourceFeatureID: FeatureID().description,
                sourceKind: .box,
                kind: .sizeX,
                label: "Size X",
                inputExpression: .length(1.5, .meter),
                resolvedMeters: 1.5,
                isPrimaryForTarget: true
            ),
        ]
    )
    let objectJSON = try JSONSerialization.jsonObject(
        with: try JSONEncoder().encode(objectSummary)
    ) as? [String: Any]
    var legacyObjectJSON = try #require(objectJSON)
    legacyObjectJSON["displayUnitSymbol"] = nil
    var legacyObjectEntry = try #require(
        (legacyObjectJSON["entries"] as? [[String: Any]])?.first
    )
    legacyObjectEntry["valueKind"] = nil
    legacyObjectEntry["resolvedDisplayValue"] = nil
    legacyObjectEntry["resolvedDisplayUnitSymbol"] = nil
    legacyObjectJSON["entries"] = [legacyObjectEntry]

    let decodedObject = try JSONDecoder().decode(
        ObjectDimensionSummaryResult.self,
        from: try JSONSerialization.data(withJSONObject: legacyObjectJSON)
    )

    let decodedObjectEntry = try #require(decodedObject.entries.first)
    #expect(decodedObject.displayUnitSymbol == "cm")
    #expect(decodedObjectEntry.valueKind == .length)
    #expect(abs(decodedObjectEntry.resolvedDisplayValue - 150.0) < 1.0e-12)
    #expect(decodedObjectEntry.resolvedDisplayUnitSymbol == "cm")

    let sketchTarget = SelectionTarget(sceneNodeID: SceneNodeID())
    let sketchSummary = SketchDimensionSummaryResult(
        displayUnit: .centimeter,
        entries: [
            SketchDimensionSummaryResult.Entry(
                requestedTarget: sketchTarget,
                target: sketchTarget,
                sceneNodeID: sketchTarget.sceneNodeID.description,
                sourceFeatureID: FeatureID().description,
                entityID: SketchEntityID().description,
                entityKind: "line",
                kind: .angle,
                label: "Angle",
                inputExpression: .angle(Double.pi / 2.0, .radian),
                resolvedValue: Double.pi / 2.0,
                isPrimaryForTarget: true
            ),
        ]
    )
    let sketchJSON = try JSONSerialization.jsonObject(
        with: try JSONEncoder().encode(sketchSummary)
    ) as? [String: Any]
    var legacySketchJSON = try #require(sketchJSON)
    legacySketchJSON["displayUnitSymbol"] = nil
    var legacySketchEntry = try #require(
        (legacySketchJSON["entries"] as? [[String: Any]])?.first
    )
    legacySketchEntry["valueKind"] = nil
    legacySketchEntry["resolvedDisplayValue"] = nil
    legacySketchEntry["resolvedDisplayUnitSymbol"] = nil
    legacySketchJSON["entries"] = [legacySketchEntry]

    let decodedSketch = try JSONDecoder().decode(
        SketchDimensionSummaryResult.self,
        from: try JSONSerialization.data(withJSONObject: legacySketchJSON)
    )

    let decodedSketchEntry = try #require(decodedSketch.entries.first)
    #expect(decodedSketch.displayUnitSymbol == "cm")
    #expect(decodedSketchEntry.valueKind == .angle)
    #expect(abs(decodedSketchEntry.resolvedDisplayValue - 90.0) < 1.0e-12)
    #expect(decodedSketchEntry.resolvedDisplayUnitSymbol == "deg")
}

@Test func dimensionSummaryEntriesUseReadableLengthUnits() throws {
    let objectTarget = SelectionTarget(sceneNodeID: SceneNodeID())
    let objectSummary = ObjectDimensionSummaryResult(
        displayUnit: .millimeter,
        entries: [
            ObjectDimensionSummaryResult.Entry(
                target: objectTarget,
                sceneNodeID: objectTarget.sceneNodeID.description,
                sourceFeatureID: FeatureID().description,
                sourceKind: .box,
                kind: .sizeX,
                label: "Size X",
                inputExpression: .length(1_500.0, .meter),
                resolvedMeters: 1_500.0,
                isPrimaryForTarget: true
            ),
        ]
    )
    let objectEntry = try #require(objectSummary.entries.first)

    let sketchTarget = SelectionTarget(sceneNodeID: SceneNodeID())
    let sketchSummary = SketchDimensionSummaryResult(
        displayUnit: .meter,
        entries: [
            SketchDimensionSummaryResult.Entry(
                requestedTarget: sketchTarget,
                target: sketchTarget,
                sceneNodeID: sketchTarget.sceneNodeID.description,
                sourceFeatureID: FeatureID().description,
                entityID: SketchEntityID().description,
                entityKind: "line",
                kind: .length,
                label: "Length",
                inputExpression: .length(0.000_25, .meter),
                resolvedValue: 0.000_25,
                isPrimaryForTarget: true
            ),
        ]
    )
    let sketchEntry = try #require(sketchSummary.entries.first)

    #expect(objectSummary.displayUnit == .millimeter)
    #expect(objectEntry.resolvedDisplayValue == 1.5)
    #expect(objectEntry.resolvedDisplayUnitSymbol == "km")
    #expect(sketchSummary.displayUnit == .meter)
    #expect(abs(sketchEntry.resolvedDisplayValue - 250.0) < 1.0e-9)
    #expect(sketchEntry.resolvedDisplayUnitSymbol == "μm")
}
