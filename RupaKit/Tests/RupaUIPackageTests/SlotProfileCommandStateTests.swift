import Testing
@testable import RupaUI

@Test func slotProfileCommandStateActivatesWidthInputAndDeactivates() {
    var state = SlotProfileCommandState.inactive

    #expect(!state.isActive)
    #expect(state.inputMode == .inactive)
    #expect(state.inputModeTitle == "Inactive")

    state.activateWidthInput()
    #expect(state.isActive)
    #expect(state.inputMode == .width)
    #expect(state.inputModeTitle == "Width")

    state.deactivate()
    #expect(!state.isActive)
    #expect(state.inputMode == .inactive)
}
