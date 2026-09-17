import SwiftUI
import Testing
@testable import RupaUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct InspectorNumericInputTests {
    @Test func frozenMappingAndLatestAcknowledgement() {
        var edit = InspectorNumericEdit()
        let initial = InspectorNumericMapping.number(range: -100...100)
        edit.begin(initial)
        #expect(edit.setSlider(25, mapping: initial) == 25)
        let first = edit.submitted()
        let expanded = InspectorNumericMapping.number(range: -1000...1000)
        #expect(edit.setSlider(30, mapping: expanded) == 30)
        let last = edit.submitted()
        #expect(edit.mapping?.sliderRange == -100...100)
        edit.acknowledged(first)
        edit.end()
        #expect(edit.value == 30)
        edit.acknowledged(last)
        #expect(edit.value == nil)
        #expect(edit.mapping == nil)
        let scale = WorkspaceLengthSliderScale(metersRange: -1...1)
        var normalized = initial
        normalized.sliderRange = 0...1
        normalized.value = scale.meters
        edit.begin(normalized)
        let changedScale = WorkspaceLengthSliderScale(metersRange: -100...100)
        var changedMapping = normalized
        changedMapping.value = changedScale.meters
        #expect(abs(edit.setSlider(0.75, mapping: changedMapping) - 0.5) < 1e-10)
    }

    @Test func incompleteTextAndFailureSettlement() {
        var edit = InspectorNumericEdit()
        let mapping = InspectorNumericMapping.number(range: -10...10)
        edit.begin(mapping)
        #expect(edit.setText("-", mapping: mapping) == nil)
        #expect(edit.text == "-")
        #expect(edit.setText("1.", mapping: mapping) == 1)
        let request = edit.submitted()
        edit.acknowledged(request)
        #expect(edit.text == "1.")
        edit.end()
        #expect(edit.text == nil)
        // A failed source edit follows the same settlement: source, not the
        // requested value, supplies the idle display.
        edit.begin(mapping)
        _ = edit.setText("-2", mapping: mapping)
        let failed = edit.submitted()
        edit.end()
        edit.acknowledged(failed)
        #expect(edit.value == nil)
        let integer = InspectorNumericMapping.integer(range: 1...10_000)
        #expect(integer.parse("1e100") == nil)
        #expect(integer.parse("12") == 12)
    }

    @Test func completionObservationPreservesReplacementAndBarriers() async throws {
        let sequencer = ProjectWorkspaceOperationSequencer()
        var values: [Int] = []
        // All submissions happen synchronously before queued work can start.
        sequencer.enqueueReplacingPending(key: "x") { values.append(1) }
        let first = try #require(sequencer.currentCompletion)
        sequencer.enqueueReplacingPending(key: "x") { values.append(2) }
        let barrier = sequencer.enqueue { values.append(3) }
        sequencer.enqueueReplacingPending(key: "x") { values.append(4) }
        await sequencer.currentCompletion?.value
        await first.value
        _ = try await barrier.value
        #expect(values == [2, 3, 4])
    }

    @Test func productionSliderBindingRejectsStalePublication() async throws {
        var edit = InspectorNumericEdit()
        let binding = Binding(get: { edit }, set: { edit = $0 })
        let initialScale = WorkspaceLengthSliderScale(metersRange: -1...1)
        let initial = InspectorNumericMapping(unit: "m", sliderRange: 0...1,
            sliderValue: initialScale.sliderValue, value: initialScale.meters,
            format: { String($0) }, parse: Double.init)
        var submissions: [Double] = []
        var revisions: [Int] = []
        let submit: (Double) -> Void = {
            submissions.append($0)
            revisions.append(edit.submitted())
        }
        edit.begin(initial)
        let slider = InspectorNumericInput.sliderBinding(
            edit: binding, value: 0, mapping: initial, onChange: submit)
        slider.wrappedValue = 0.75
        let expandedScale = WorkspaceLengthSliderScale(metersRange: -100...100)
        var expanded = initial
        expanded.sliderValue = expandedScale.sliderValue
        expanded.value = expandedScale.meters
        // This is the body-recomputation path after an older source publication.
        let republished = InspectorNumericInput.sliderBinding(
            edit: binding, value: 0.1, mapping: expanded, onChange: submit)
        #expect(abs(republished.wrappedValue - 0.75) < 1e-10)
        republished.wrappedValue = 0.8
        edit.acknowledged(revisions[0])
        edit.end()
        #expect(abs(republished.wrappedValue - 0.8) < 1e-10)
        #expect(abs(submissions[0] - 0.5) < 1e-10)
        #expect(abs(submissions[1] - 0.6) < 1e-10)
        edit.acknowledged(revisions[1])
        let settled = InspectorNumericInput.sliderBinding(
            edit: binding, value: 0.6, mapping: expanded, onChange: submit)
        #expect(abs(settled.wrappedValue - expandedScale.sliderValue(forMeters: 0.6)) < 1e-10)
    }
}
