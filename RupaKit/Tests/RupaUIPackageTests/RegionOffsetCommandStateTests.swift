import RupaCore
import Testing
@testable import RupaUI

@Test func regionOffsetCommandStateActivatesDistanceAndResetsTransientOptions() {
    var state = RegionOffsetCommandState.inactive

    #expect(!state.isActive)
    #expect(state.inputModeTitle == "Inactive")

    state.activateArrowDrag()
    #expect(state.isActive)
    #expect(state.inputMode == .arrowDrag)
    #expect(state.inputModeTitle == "Arrow")

    state.activateDistanceInput()
    state.toggleLockedDistance()
    state.toggleCombinedRegions()
    #expect(state.inputMode == .distance)
    #expect(state.inputModeTitle == "Distance")
    #expect(state.usesLockedDistance)
    #expect(state.usesCombinedRegions)

    state.deactivate()
    #expect(!state.isActive)
    #expect(!state.usesLockedDistance)
    #expect(!state.usesCombinedRegions)
}

@Test func regionOffsetCommandStateCyclesGapFillInCommandOrder() {
    let state = RegionOffsetCommandState.inactive

    #expect(state.gapFill(after: .round) == .linear)
    #expect(state.gapFill(after: .linear) == .natural)
    #expect(state.gapFill(after: .natural) == .round)
}
