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
    #expect(recommendation.currentScaleProfile == nil)
    #expect(recommendation.currentComfortableModelSpanTitle == "10 mm to 800 mm")
    #expect(recommendation.recommendedScaleProfile.category == .site)
    #expect(recommendation.recommendedScaleProfile.useCaseTitle == "site, campus, and civil-scale coordination")
    #expect(recommendation.recommendedScaleProfile.visibleSpanTitle == "100 km")
    #expect(recommendation.recommendedScaleProfile.comfortableModelSpanTitle == "1 km to 80 km")
}

@Test func workspaceScaleFitPlanAppliesSitePlanningForKilometerScaleDocument() throws {
    let document = try workspaceScaleFitSiteDocument()

    let plan = try WorkspaceScaleFitService().plan(
        document: document,
        ruler: .standard(for: .millimeter)
    )

    #expect(plan.action == .applyPreset(.sitePlanning))
    #expect(plan.measurement.bounds?.maximumSpan == 25_000.0)
    #expect(plan.recommendation?.recommendedPreset == .sitePlanning)
    #expect(plan.recommendation?.recommendedScale.displayUnit == .kilometer)
}

@Test func workspaceScaleRecommendationChoosesUrbanPlanningForDistrictScaleModel() throws {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 5_000.0,
        maxY: 2_000.0,
        maxZ: 100.0
    )

    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: bounds,
        currentRuler: WorkspaceScalePreset.architecture.rulerConfiguration
    ))

    #expect(recommendation.reason == .modelExceedsComfortableSpan)
    #expect(recommendation.modelSpanMeters == 5_000.0)
    #expect(recommendation.recommendedPreset == .urbanPlanning)
    #expect(recommendation.recommendedScale.displayUnit == .kilometer)
    #expect(recommendation.recommendedScale.visibleSpanMeters == 25_000.0)
    #expect(recommendation.recommendedScale.visibleSpanDisplayValue == 25.0)
    #expect(recommendation.currentScaleProfile?.preset == .architecture)
    #expect(recommendation.currentComfortableModelSpanTitle == "20 m to 1.6 km")
    #expect(recommendation.recommendedScaleProfile.category == .urban)
    #expect(recommendation.recommendedScaleProfile.visibleSpanTitle == "25 km")
    #expect(recommendation.recommendedScaleProfile.comfortableModelSpanTitle == "0.25 km to 20 km")
}

@Test func workspaceScaleFitPlanAppliesUrbanPlanningForDistrictScaleDocument() throws {
    var document = DesignDocument.empty(named: "Fit Urban")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Fit Urban Footprint",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(5_000.0, .meter),
            y: .length(2_000.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Fit Urban Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(100.0, .meter),
        direction: .normal
    )

    let plan = try WorkspaceScaleFitService().plan(
        document: document,
        ruler: .standard(for: .millimeter)
    )

    #expect(plan.action == .applyPreset(.urbanPlanning))
    #expect(plan.measurement.bounds?.maximumSpan == 5_000.0)
    #expect(plan.recommendation?.recommendedPreset == .urbanPlanning)
    #expect(plan.recommendation?.recommendedScale.displayUnit == .kilometer)
}

@Test func workspaceScaleFitPlanReportsAlreadyFittingDocument() throws {
    let document = try workspaceScaleFitSiteDocument()

    let plan = try WorkspaceScaleFitService().plan(
        document: document,
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )

    #expect(plan.action == .alreadyFits)
    #expect(plan.measurement.bounds?.maximumSpan == 25_000.0)
    #expect(plan.recommendation == nil)
}

@Test func workspaceScaleFitPlanReportsUnsupportedRegionalRange() throws {
    var document = DesignDocument.empty(named: "Unsupported Regional")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Regional Footprint",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1_200_000.0, .meter),
            y: .length(400_000.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Regional Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(1_000.0, .meter),
        direction: .normal
    )

    let plan = try WorkspaceScaleFitService().plan(
        document: document,
        ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    )

    #expect(plan.action == .unsupportedRange)
    #expect(plan.measurement.bounds?.maximumSpan == 1_200_000.0)
    #expect(plan.recommendation?.reason == .modelExceedsSupportedScaleRange)
    #expect(plan.recommendation?.recommendedPreset == .regionalPlanning)
    #expect(plan.recommendation?.isActionable == false)
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
    #expect(recommendation.currentScaleProfile?.preset == .sitePlanning)
    #expect(recommendation.currentComfortableModelSpanTitle == "1 km to 80 km")
    #expect(recommendation.recommendedScaleProfile.category == .regional)
    #expect(recommendation.recommendedScaleProfile.visibleSpanTitle == "1,000 km")
    #expect(recommendation.recommendedScaleProfile.comfortableModelSpanTitle == "10 km to 800 km")
}

@Test func workspaceScaleRecommendationWarnsWhenModelExceedsLargestMetricScaleRange() throws {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 1_200_000.0,
        maxY: 400_000.0,
        maxZ: 1_000.0
    )

    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: bounds,
        currentRuler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    ))

    #expect(recommendation.reason == .modelExceedsSupportedScaleRange)
    #expect(recommendation.modelSpanMeters == 1_200_000.0)
    #expect(recommendation.recommendedPreset == .regionalPlanning)
    #expect(recommendation.recommendedScale.displayUnit == .kilometer)
    #expect(recommendation.recommendedScaleProfile.visibleSpanTitle == "1,000 km")
    #expect(recommendation.recommendedScaleProfile.comfortableModelSpanTitle == "10 km to 800 km")
    #expect(recommendation.isActionable == false)

    let diagnostics = WorkspaceScaleRecommendationService().diagnostics(for: recommendation)
    #expect(diagnostics.first?.severity == .warning)
    #expect(diagnostics.first?.code == .workspaceScaleWarning)
    #expect(diagnostics.first?.message.contains("largest supported comfortable range") == true)
    #expect(diagnostics.first?.message.contains("segment the context") == true)
}

@Test func workspaceScaleRecommendationStillRecommendsLargestPresetForOversizeModelFromSmallerScale() throws {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 1_200_000.0,
        maxY: 400_000.0,
        maxZ: 1_000.0
    )

    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: bounds,
        currentRuler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    ))

    #expect(recommendation.reason == .modelExceedsSupportedScaleRange)
    #expect(recommendation.recommendedPreset == .regionalPlanning)
    #expect(recommendation.isActionable)
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
    #expect(recommendation.currentScaleProfile?.preset == .sitePlanning)
    #expect(recommendation.currentComfortableModelSpanTitle == "1 km to 80 km")
    #expect(recommendation.recommendedScaleProfile.category == .product)
    #expect(recommendation.recommendedScaleProfile.comfortableModelSpanTitle == "100 mm to 8 m")
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

    let result = try MeasurementService().measure(
        document: document,
        ruler: .standard(for: .millimeter)
    )

    #expect(result.workspaceScaleRecommendation?.recommendedPreset == .sitePlanning)
    #expect(result.workspaceScaleRecommendation?.recommendedScale.displayUnit == .kilometer)
    #expect(result.workspaceScaleRecommendation?.recommendedScaleProfile.useCaseTitle == "site, campus, and civil-scale coordination")
    #expect(result.workspaceScaleRecommendation?.recommendedScaleProfile.comfortableModelSpanTitle == "1 km to 80 km")
    #expect(result.diagnostics.contains {
        $0.severity == .info
            && $0.code == .workspaceScaleRecommendation
            && $0.message.contains("Site Planning")
            && $0.message.contains("1 km to 80 km")
    })
}

@MainActor
@Test func evaluationSnapshotExcludesWorkspaceScaleAndDisplaySnapshotRecommendsIt() throws {
    var document = DesignDocument.empty(named: "Evaluated Site")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Evaluated Site Footprint",
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
        name: "Evaluated Site Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(100.0, .meter),
        direction: .normal
    )

    let evaluation = EvaluationScheduler().evaluate(
        document: document,
        generation: DocumentGeneration(1)
    )
    let display = try DesignDisplaySnapshotService().result(
        document: document,
        workspaceState: WorkspaceState(),
        generation: DocumentGeneration(1),
        dirty: false
    )

    #expect(evaluation.status == .valid)
    #expect(!evaluation.diagnostics.contains {
        $0.code == .workspaceScaleRecommendation || $0.code == .workspaceScaleWarning
    })
    #expect(display.workspaceScaleRecommendation?.recommendedPreset == .sitePlanning)
    #expect(display.workspaceScaleRecommendation?.recommendedScale.displayUnit == .kilometer)
    #expect(display.workspaceScaleRecommendation?.recommendedScaleProfile.comfortableModelSpanTitle == "1 km to 80 km")
}

@MainActor
@Test func measurementIncludesWorkspaceScaleWarningForModelBeyondLargestPreset() throws {
    var document = DesignDocument.empty(named: "Regional Context")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Regional Footprint",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1_200_000.0, .meter),
            y: .length(400_000.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Regional Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(1_000.0, .meter),
        direction: .normal
    )

    let result = try MeasurementService().measure(
        document: document,
        ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    )

    #expect(result.workspaceScaleRecommendation?.reason == .modelExceedsSupportedScaleRange)
    #expect(result.workspaceScaleRecommendation?.isActionable == false)
    #expect(result.workspaceScaleRecommendation?.recommendedPreset == .regionalPlanning)
    #expect(result.diagnostics.contains {
        $0.severity == .warning
            && $0.code == .workspaceScaleWarning
            && $0.message.contains("largest supported comfortable range")
    })
}

private func workspaceScaleFitSiteDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Fit Site")
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Fit Site Footprint",
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
        name: "Fit Site Mass",
        profile: ProfileReference(featureID: profileID),
        distance: .length(100.0, .meter),
        direction: .normal
    )
    return document
}
