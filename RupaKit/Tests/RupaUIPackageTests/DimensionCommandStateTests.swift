import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func dimensionCommandStateActivatesPrimaryCandidateInDisplayMode() {
    var state = DimensionCommandState.inactive

    state.activate(entries: [
        dimensionEntry(source: .object(.sizeX), label: "Size X", resolvedValue: 0.010, valueKind: .length),
        dimensionEntry(source: .object(.sizeY), label: "Size Y", resolvedValue: 0.020, valueKind: .length, isPrimary: true),
    ])

    #expect(state.isActive)
    #expect(state.activeEntry?.source == .object(.sizeY))
    #expect(state.currentValue == 0.020)
    #expect(!state.isInputModeActive)
    #expect(state.activeOrdinal == 2)
    #expect(state.activeCount == 2)
}

@Test func dimensionCommandStateTabEntersInputModeThenCyclesCandidates() {
    var state = DimensionCommandState.inactive

    state.activate(entries: [
        dimensionEntry(source: .sketch(.length), label: "Length", resolvedValue: 0.010, valueKind: .length),
        dimensionEntry(source: .sketch(.angle), label: "Angle", resolvedValue: .pi / 2.0, valueKind: .angle, isPrimary: true),
    ])

    state.handleTab()

    #expect(state.isInputModeActive)
    #expect(state.activeEntry?.source == .sketch(.angle))
    #expect(state.currentValue == .pi / 2.0)

    state.handleTab()

    #expect(state.isInputModeActive)
    #expect(state.activeEntry?.source == .sketch(.length))
    #expect(state.currentValue == 0.010)
}

@Test func dimensionCommandStateRejectsInvalidLengthDraftValues() {
    var state = DimensionCommandState.inactive

    state.activate(entries: [
        dimensionEntry(source: .object(.diameter), label: "Diameter", resolvedValue: 0.030, valueKind: .length, isPrimary: true),
    ])
    state.activateInputMode()
    state.setDraftValue(0.0)
    state.setDraftValue(.infinity)

    #expect(state.currentValue == 0.030)
    #expect(state.canCommit)

    state.setDraftValue(0.050)

    #expect(state.currentValue == 0.050)
    #expect(state.canCommit)
}

@Test func dimensionCommandStateAcceptsExplicitLengthDraftText() {
    var state = DimensionCommandState.inactive

    state.activate(entries: [
        dimensionEntry(source: .object(.sizeX), label: "Size X", resolvedValue: 0.030, valueKind: .length, isPrimary: true),
    ])
    state.activateInputMode()
    state.setDraftText("1 km", defaultUnit: .millimeter)

    #expect(state.currentValue == 1_000.0)
    #expect(state.canCommit)

    state.setDraftText("6' 4\"", defaultUnit: .millimeter)

    let expectedMeters = LengthDisplayUnit.foot.meters(from: 6.0)
        + LengthDisplayUnit.inch.meters(from: 4.0)
    #expect(abs((state.currentValue ?? 0.0) - expectedMeters) < 0.000_000_000_001)
}

@Test func dimensionCommandStateUsesProvidedLengthDefaultUnitForUnmarkedDraftText() {
    var state = DimensionCommandState.inactive

    state.activate(entries: [
        dimensionEntry(source: .object(.sizeX), label: "Size X", resolvedValue: 1_000.0, valueKind: .length, isPrimary: true),
    ])
    state.activateInputMode()
    state.setDraftText("2", defaultUnit: .kilometer)

    #expect(state.currentValue == 2_000.0)
    #expect(state.canCommit)
}

@Test func dimensionCommandStateAllowsFiniteAngleDraftValues() {
    var state = DimensionCommandState.inactive

    state.activate(entries: [
        dimensionEntry(source: .sketch(.angle), label: "Angle", resolvedValue: 0.0, valueKind: .angle, isPrimary: true),
    ])
    state.activateInputMode()
    state.setDraftValue(-.pi / 4.0)

    #expect(state.currentValue == -.pi / 4.0)
    #expect(state.canCommit)
}

@Test func dimensionCommandStateAcceptsAngleDraftTextInDegrees() {
    var state = DimensionCommandState.inactive

    state.activate(entries: [
        dimensionEntry(source: .sketch(.angle), label: "Angle", resolvedValue: 0.0, valueKind: .angle, isPrimary: true),
    ])
    state.activateInputMode()
    state.setDraftText("90", defaultUnit: .millimeter)

    #expect(abs((state.currentValue ?? 0.0) - Double.pi / 2.0) < 0.000_000_000_001)
    #expect(state.canCommit)
}

private func dimensionEntry(
    source: DimensionCommandEntry.Source,
    label: String,
    resolvedValue: Double,
    valueKind: DimensionCommandEntry.ValueKind,
    isPrimary: Bool = false
) -> DimensionCommandEntry {
    DimensionCommandEntry(
        target: SelectionTarget(sceneNodeID: SceneNodeID()),
        source: source,
        label: label,
        sourceTitle: "Test",
        resolvedValue: resolvedValue,
        valueKind: valueKind,
        isPrimaryForTarget: isPrimary
    )
}
