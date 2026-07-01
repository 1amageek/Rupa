import Testing
@testable import RupaCore
@testable import RupaUI

@Test func commonWorkspaceInspectorValueAcceptsFiniteEqualValues() {
    #expect(commonWorkspaceInspectorValue([2.0, 2.0 + 5.0e-10]) == 2.0)
}

@Test func commonWorkspaceInspectorValueRejectsMixedAndInvalidValues() {
    #expect(commonWorkspaceInspectorValue([2.0, 2.1]) == nil)
    #expect(commonWorkspaceInspectorValue([2.0, .nan]) == nil)
    #expect(commonWorkspaceInspectorValue([]) == nil)
}

@Test func workspaceInspectorNumberTextSupportsGroupedLargeValues() {
    #expect(WorkspaceInspectorNumberText.string(from: 100_000.0) == "100,000")
    #expect(WorkspaceInspectorNumberText.value(from: "100,000") == 100_000.0)
    #expect(WorkspaceInspectorNumberText.value(from: "100_000") == 100_000.0)
    #expect(WorkspaceInspectorNumberText.value(from: " 12.5 ") == 12.5)
    #expect(WorkspaceInspectorNumberText.value(from: "not-a-number") == nil)
}

@Test func workspaceInspectorLengthTextGroupsArchitecturalScaleValues() {
    #expect(
        WorkspaceInspectorNumberText.lengthString(
            fromMeters: 100_000.0,
            unit: .meter
        ) == "100,000 m"
    )
    #expect(
        WorkspaceInspectorNumberText.lengthString(
            fromMeters: 30_480.0,
            unit: .foot
        ) == "100,000 ft"
    )
}

@Test func workspaceInspectorLayoutKeepsDensePropertyPanelRhythm() {
    #expect(WorkspaceInspectorLayout.panelHorizontalInset == 12)
    #expect(WorkspaceInspectorLayout.sectionSpacing == 12)
    #expect(WorkspaceInspectorLayout.rowMinimumHeight == 26)
    #expect(WorkspaceInspectorLayout.labelWidth < 124)
    let expectedSliderLeadingPadding = WorkspaceInspectorLayout.rowHorizontalPadding
        + inspectorLabelWidth
        + inspectorRowSpacing
    #expect(abs(inspectorSliderLeadingPadding - expectedSliderLeadingPadding) < 0.01)
}

@Test func rulerScaleControlUsesLogMetersAcrossSupportedCADRange() {
    let lowSlider = RulerScaleControl.sliderValue(
        fromMeters: RulerConfiguration.minorTickMetersRange.lowerBound,
        for: .minor
    )
    let highSlider = RulerScaleControl.sliderValue(
        fromMeters: RulerConfiguration.visibleSpanMetersRange.upperBound,
        for: .visible
    )
    let visibleMeters = RulerScaleControl.meters(
        fromSliderValue: highSlider,
        for: .visible
    )

    #expect(lowSlider < highSlider)
    #expect(abs(visibleMeters - RulerConfiguration.visibleSpanMetersRange.upperBound) < 0.001)
}

@Test func rulerScaleControlKeepsTextInputInDisplayUnitsButClampsInMeters() {
    let requestedMeters = RulerScaleControl.meters(
        fromFieldValue: 2_000_000_000.0,
        unit: .millimeter,
        for: .visible
    )
    let displayedMillimeters = RulerScaleControl.fieldValue(
        fromMeters: RulerConfiguration.visibleSpanMetersRange.upperBound,
        unit: .millimeter,
        for: .visible
    )

    #expect(requestedMeters == RulerConfiguration.visibleSpanMetersRange.upperBound)
    #expect(displayedMillimeters == 1_000_000_000.0)
}

@Test func rulerScaleControlAcceptsGroupedLargeWorkspaceValues() {
    let commaMeters = RulerScaleControl.meters(
        fromFieldText: "1,000,000",
        unit: .meter,
        for: .visible
    )
    let underscoreMeters = RulerScaleControl.meters(
        fromFieldText: "1_000_000",
        unit: .meter,
        for: .visible
    )
    let imperialFeet = RulerScaleControl.meters(
        fromFieldText: "3,280,840",
        unit: .foot,
        for: .visible
    )

    #expect(commaMeters == RulerConfiguration.visibleSpanMetersRange.upperBound)
    #expect(underscoreMeters == RulerConfiguration.visibleSpanMetersRange.upperBound)
    #expect(abs((imperialFeet ?? 0.0) - RulerConfiguration.visibleSpanMetersRange.upperBound) < 1.0)
    #expect(RulerScaleControl.meters(fromFieldText: "not-a-number", unit: .meter, for: .visible) == nil)
}
