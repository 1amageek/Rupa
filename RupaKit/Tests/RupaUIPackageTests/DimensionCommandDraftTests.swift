import RupaCore
import Testing
@testable import RupaUI

/// Tab keeps each typed dimension, and Enter commits every one of them.
@Suite struct DimensionCommandDraftTests {
    private func entry(_ label: String, _ value: Double) -> DimensionCommandEntry {
        DimensionCommandEntry(
            target: SelectionTarget(sceneNodeID: SceneNodeID()), source: .object(.sizeX), label: label,
            sourceTitle: "Box", resolvedValue: value, valueKind: .length, isPrimaryForTarget: label == "X"
        )
    }

    @Test func valuesTypedBeforeTabAreKeptAndAllCommitted() {
        var state = DimensionCommandState()
        state.activate(entries: [entry("X", 1), entry("Y", 2), entry("Z", 3)])
        state.handleTab()
        state.setDraftValue(1.5)
        state.handleTab()
        #expect(state.activeEntry?.label == "Y")
        #expect(state.currentValue == 2)
        state.setDraftValue(2.5)
        state.handleTab()
        state.handleTab()
        #expect(state.activeEntry?.label == "X")
        #expect(state.currentValue == 1.5, "Returning to an entry shows the value typed there.")
        #expect(state.pendingValues.map(\.entry.label) == ["X", "Y"])
        #expect(state.pendingValues.map(\.value) == [1.5, 2.5])
        state.deactivate()
        #expect(state.pendingValues.isEmpty)
    }
}
