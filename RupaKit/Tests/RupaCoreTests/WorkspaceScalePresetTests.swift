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
