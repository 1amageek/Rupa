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

@Test func slotProfileCommandStateRunsOffsetVertexOnACurveEnd() {
    var state = SlotProfileCommandState.inactive
    state.beginVertexOffset()
    #expect(state.isVertexOffsetActive)
    #expect(!state.isCurveOffsetActive)
    #expect(state.title == "Offset Vertex")
    #expect(state.inputModeTitle == "Distance")

    // O on a curve afterwards starts Offset, not Slot.
    state.pressOffsetKey()
    #expect(state.isCurveOffsetActive)
    #expect(!state.isVertexOffsetActive)
    state.deactivate()
    #expect(!state.isActive)
}
