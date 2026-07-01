import RupaCore
import Testing
@testable import RupaRendering

@Test func viewportInteractionScaleDefaultsMatchMillimeterWorkspace() {
    let defaults = ViewportInteractionScaleDefaults(ruler: .standard(for: .millimeter))

    #expect(defaults.operationStepMeters == 0.001)
    #expect(defaults.slotWidthMeters == 0.002)
}

@Test func viewportInteractionScaleDefaultsFollowSitePlanningWorkspace() {
    let defaults = ViewportInteractionScaleDefaults(
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )

    #expect(defaults.operationStepMeters == 100.0)
    #expect(defaults.slotWidthMeters == 200.0)
}
