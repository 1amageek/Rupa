import SwiftCAD
import Testing
@testable import RupaCore

@Test func workspaceScaleRecommendationChoosesSitePlanningForKilometerScaleModel() throws {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 25_000.0,
        maxY: 10_000.0,
        maxZ: 100.0
    )

    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: bounds,
        currentRuler: RulerConfiguration.standard(for: .millimeter)
    ))

    #expect(recommendation.reason == .modelExceedsComfortableSpan)
    #expect(recommendation.modelSpanMeters == 25_000.0)
    #expect(recommendation.recommendedPreset == .sitePlanning)
    #expect(recommendation.recommendedScale.displayUnit == .kilometer)
    #expect(recommendation.recommendedScale.visibleSpanMeters == 100_000.0)
    #expect(recommendation.recommendedScale.visibleSpanDisplayValue == 100.0)
}

@Test func workspaceScaleRecommendationChoosesRegionalPlanningForHundredsOfKilometersModel() throws {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 250_000.0,
        maxY: 120_000.0,
        maxZ: 1_000.0
    )

    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: bounds,
        currentRuler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    ))

    #expect(recommendation.reason == .modelExceedsComfortableSpan)
    #expect(recommendation.modelSpanMeters == 250_000.0)
    #expect(recommendation.recommendedPreset == .regionalPlanning)
    #expect(recommendation.recommendedScale.displayUnit == .kilometer)
    #expect(recommendation.recommendedScale.visibleSpanMeters == 1_000_000.0)
    #expect(recommendation.recommendedScale.visibleSpanDisplayValue == 1_000.0)
}

@Test func workspaceScaleRecommendationChoosesSmallerPresetForTinyModelInSiteWorkspace() throws {
    let bounds = MeasurementResult.Bounds(
        minX: -0.25,
        minY: -0.25,
        minZ: 0.0,
        maxX: 0.25,
        maxY: 0.25,
        maxZ: 0.25
    )

    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: bounds,
        currentRuler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    ))

    #expect(recommendation.reason == .modelTooSmallForWorkspace)
    #expect(recommendation.modelSpanMeters == 0.5)
    #expect(recommendation.recommendedPreset == .productDesign)
    #expect(recommendation.recommendedScale.displayUnit == .millimeter)
}

@Test func workspaceScaleRecommendationIgnoresComfortablyFramedModel() {
    let bounds = MeasurementResult.Bounds(
        minX: -10.0,
        minY: -5.0,
        minZ: 0.0,
        maxX: 10.0,
        maxY: 5.0,
        maxZ: 3.0
    )

    let recommendation = WorkspaceScaleRecommendationService().recommendation(
        for: bounds,
        currentRuler: WorkspaceScalePreset.roomInterior.rulerConfiguration
    )

    #expect(recommendation == nil)
}

@MainActor
@Test func measurementIncludesWorkspaceScaleRecommendationForSiteModel() throws {
    var document = DesignDocument.empty(named: "Site")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Site Footprint",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(25_000.0, .meter),
            y: .length(10_000.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Site Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(100.0, .meter),
        direction: .normal
    )

    let result = try MeasurementService().measure(document: document)

    #expect(result.workspaceScaleRecommendation?.recommendedPreset == .sitePlanning)
    #expect(result.workspaceScaleRecommendation?.recommendedScale.displayUnit == .kilometer)
    #expect(result.diagnostics.contains {
        $0.severity == .info
            && $0.message.contains("Workspace scale recommendation")
            && $0.message.contains("Site Planning")
    })
}
