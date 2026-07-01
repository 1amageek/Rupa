import Testing
@testable import RupaCore

@Test func workspaceScalePresetProfilesExposeUseCasesAndComfortRanges() {
    let precision = WorkspaceScalePreset.precisionMechanical.profile
    let regional = WorkspaceScalePreset.regionalPlanning.profile

    #expect(precision.category == .mechanical)
    #expect(precision.displayUnit == .millimeter)
    #expect(precision.visibleSpanTitle == "1 m")
    #expect(precision.comfortableModelSpanTitle == "10 mm to 800 mm")
    #expect(precision.agentGuidance.contains("precisionMechanical"))
    #expect(precision.agentGuidance.contains("comfortable model span 10 mm to 800 mm"))

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
    let regional = WorkspaceScalePreset.regionalPlanning.profile

    #expect(WorkspaceScalePreset.minimumComfortableModelSpanRatio == 0.01)
    #expect(WorkspaceScalePreset.maximumComfortableModelSpanRatio == 0.80)
    #expect(regional.comfortableModelSpanLowerMeters == 10_000.0)
    #expect(regional.comfortableModelSpanUpperMeters == 800_000.0)
}
