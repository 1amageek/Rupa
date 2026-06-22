import RupaCore
@testable import RupaUI
import Testing

@Test func edgeOffsetCommandStateActivatesDistanceAndDeactivates() {
    var state = EdgeOffsetCommandState.inactive

    #expect(state.isActive == false)
    #expect(state.inputModeTitle == "Inactive")

    state.activateDistanceInput()

    #expect(state.isActive)
    #expect(state.inputMode == .distance)
    #expect(state.inputModeTitle == "Distance")

    state.deactivate()

    #expect(state == .inactive)
}

@Test func edgeOffsetCommandStateCyclesGapFillInCommandOrder() {
    let state = EdgeOffsetCommandState.inactive

    #expect(state.gapFill(after: .round) == .linear)
    #expect(state.gapFill(after: .linear) == .natural)
    #expect(state.gapFill(after: .natural) == .round)
}
