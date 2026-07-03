import Testing
@testable import RupaCore

@Test func workspaceScalePresetProfilesExposeUseCasesAndComfortRanges() {
    let precision = WorkspaceScalePreset.precisionMechanical.profile
    let urban = WorkspaceScalePreset.urbanPlanning.profile
    let regional = WorkspaceScalePreset.regionalPlanning.profile

    #expect(precision.category == .mechanical)
    #expect(precision.displayUnit == .millimeter)
    #expect(precision.visibleSpanTitle == "1 m")
    #expect(precision.comfortableModelSpanTitle == "10 mm to 800 mm")
    #expect(precision.agentGuidance.contains("precisionMechanical"))
    #expect(precision.agentGuidance.contains("comfortable model span 10 mm to 800 mm"))

    #expect(urban.category == .urban)
    #expect(urban.displayUnit == .kilometer)
    #expect(urban.minorTickTitle == "10 m")
    #expect(urban.majorTickTitle == "0.1 km")
    #expect(urban.visibleSpanTitle == "25 km")
    #expect(urban.comfortableModelSpanTitle == "0.25 km to 20 km")
    #expect(urban.menuTitle == "Urban Planning · 25 km")
    #expect(urban.agentGuidance.contains("urbanPlanning"))
    #expect(urban.agentGuidance.contains("large site coordination"))

    #expect(regional.category == .regional)
    #expect(regional.displayUnit == .kilometer)
    #expect(regional.minorTickTitle == "1 km")
    #expect(regional.majorTickTitle == "10 km")
    #expect(regional.visibleSpanTitle == "1,000 km")
    #expect(regional.comfortableModelSpanTitle == "10 km to 800 km")
    #expect(regional.menuTitle == "Regional Planning · 1,000 km")
    #expect(regional.summary.contains("unit km"))
    #expect(regional.agentGuidance.contains("regionalPlanning"))
    #expect(regional.agentGuidance.contains("visible span 1,000 km"))
}

@Test func workspaceScaleRecommendationUsesPresetComfortRangeConstants() {
    let urban = WorkspaceScalePreset.urbanPlanning.profile
    let regional = WorkspaceScalePreset.regionalPlanning.profile

    #expect(WorkspaceScalePreset.minimumComfortableModelSpanRatio == 0.01)
    #expect(WorkspaceScalePreset.maximumComfortableModelSpanRatio == 0.80)
    #expect(urban.comfortableModelSpanLowerMeters == 250.0)
    #expect(urban.comfortableModelSpanUpperMeters == 20_000.0)
    #expect(regional.comfortableModelSpanLowerMeters == 10_000.0)
    #expect(regional.comfortableModelSpanUpperMeters == 800_000.0)
}
