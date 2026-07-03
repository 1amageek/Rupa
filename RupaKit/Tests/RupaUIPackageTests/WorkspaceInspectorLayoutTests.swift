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
        ) == "100,000' 0\""
    )
    #expect(
        WorkspaceInspectorNumberText.lengthString(
            fromMeters: LengthDisplayUnit.foot.meters(from: 6.0)
                + LengthDisplayUnit.inch.meters(from: 4.5),
            unit: .foot
        ) == "6' 4 1/2\""
    )
}

@Test func workspaceInspectorReadableLengthTextScalesMetricRanges() {
    #expect(
        WorkspaceInspectorNumberText.readableLengthString(
            fromMeters: 1_500.0,
            preferredUnit: .millimeter
        ) == "1.5 km"
    )
    #expect(
        WorkspaceInspectorNumberText.readableLengthString(
            fromMeters: 1_500.0,
            preferredUnit: .millimeter,
            allowsKilometers: true
        ) == "1.5 km"
    )
    #expect(
        WorkspaceInspectorNumberText.readableLengthString(
            fromMeters: 0.000_25,
            preferredUnit: .meter
        ) == "250 μm"
    )
    #expect(
        WorkspaceInspectorNumberText.readableLengthString(
            fromMeters: 0.512,
            preferredUnit: .millimeter
        ) == "512 mm"
    )
}

@Test func workspaceLengthFieldPresentationUsesReadableUnits() {
    let large = workspaceLengthFieldPresentation(
        fromMeters: 1_000.0,
        preferredUnit: .millimeter
    )
    let scaleLarge = workspaceLengthFieldPresentation(
        fromMeters: 1_000.0,
        preferredUnit: .millimeter,
        policy: .workspaceScale
    )
    let intermediate = workspaceLengthFieldPresentation(
        fromMeters: 0.02,
        preferredUnit: .meter
    )
    let small = workspaceLengthFieldPresentation(
        fromMeters: 0.000_25,
        preferredUnit: .meter
    )

    #expect(large.unit == .kilometer)
    #expect(large.value == 1.0)
    #expect(large.text == "1")
    #expect(scaleLarge.unit == .kilometer)
    #expect(scaleLarge.value == 1.0)
    #expect(scaleLarge.text == "1")
    #expect(intermediate.unit == .centimeter)
    #expect(intermediate.value == 2.0)
    #expect(intermediate.text == "2")
    #expect(small.unit == .micrometer)
    #expect(small.value == 250.0)
    #expect(small.text == "250")
}

@Test func workspaceLengthMetersAcceptsExplicitUnitsIndependentOfDisplayUnit() {
    let kilometerMeters = workspaceLengthMeters(
        fromFieldText: "1 km",
        defaultUnit: .millimeter
    )
    let micrometerMeters = workspaceLengthMeters(
        fromFieldText: "250 um",
        defaultUnit: .meter
    )
    let expressionMeters = workspaceLengthMeters(
        fromFieldText: "1 km / 2",
        defaultUnit: .millimeter
    )

    #expect(kilometerMeters == 1_000.0)
    #expect(micrometerMeters == 0.000_25)
    #expect(expressionMeters == 500.0)
    #expect(workspaceLengthMeters(fromFieldText: "not-a-length", defaultUnit: .meter) == nil)
}

@Test func workspaceLengthMetersAcceptsArchitecturalFeetInches() {
    let markedMeters = workspaceLengthMeters(
        fromFieldText: "6' 4\"",
        defaultUnit: .millimeter
    )
    let wordMeters = workspaceLengthMeters(
        fromFieldText: "6 ft 4 1/2 in",
        defaultUnit: .millimeter
    )

    let expectedMarkedMeters = LengthDisplayUnit.foot.meters(from: 6.0)
        + LengthDisplayUnit.inch.meters(from: 4.0)
    let expectedWordMeters = LengthDisplayUnit.foot.meters(from: 6.0)
        + LengthDisplayUnit.inch.meters(from: 4.5)

    #expect(abs((markedMeters ?? 0.0) - expectedMarkedMeters) < 0.000_000_000_001)
    #expect(abs((wordMeters ?? 0.0) - expectedWordMeters) < 0.000_000_000_001)
}

@Test func workspaceLengthSliderScaleKeepsNormalRangesLinear() {
    let scale = WorkspaceLengthSliderScale(metersRange: 0.0 ... 10.0)

    #expect(scale.sliderValue(forMeters: 5.0) == 0.5)
    #expect(scale.meters(fromSliderValue: 0.25) == 2.5)
}

@Test func workspaceLengthSliderScaleUsesLogForLargePositiveRanges() {
    let scale = WorkspaceLengthSliderScale(metersRange: 0.0 ... 1_000_000.0)
    let smallValue = scale.sliderValue(forMeters: 1.0)
    let mediumValue = scale.sliderValue(forMeters: 1_000.0)
    let roundTrippedMeters = scale.meters(fromSliderValue: mediumValue)

    #expect(smallValue > 0.0)
    #expect(smallValue < mediumValue)
    #expect(mediumValue < 1.0)
    #expect(abs(roundTrippedMeters - 1_000.0) < 0.000_001)
    #expect(scale.meters(fromSliderValue: 0.0) == 0.0)
    #expect(abs(scale.meters(fromSliderValue: 1.0) - 1_000_000.0) < 0.001)
}

@Test func workspaceLengthSliderScaleUsesSymmetricLogForLargePositionRanges() {
    let scale = WorkspaceLengthSliderScale(metersRange: -1_000_000.0 ... 1_000_000.0)
    let positiveValue = scale.sliderValue(forMeters: 1_000.0)
    let negativeValue = scale.sliderValue(forMeters: -1_000.0)
    let positiveMeters = scale.meters(fromSliderValue: positiveValue)
    let negativeMeters = scale.meters(fromSliderValue: negativeValue)

    #expect(scale.sliderValue(forMeters: 0.0) == 0.5)
    #expect(scale.meters(fromSliderValue: 0.5) == 0.0)
    #expect(positiveValue > 0.5)
    #expect(negativeValue < 0.5)
    #expect(abs(positiveMeters - 1_000.0) < 0.000_001)
    #expect(abs(negativeMeters + 1_000.0) < 0.000_001)
}

@Test func workspaceScaleFactorSliderScaleUsesLogForWideTransformRanges() {
    let scale = WorkspaceScaleFactorSliderScale(valueRange: 1.0e-9 ... 1.0e9)
    let smallValue = scale.sliderValue(for: 1.0e-6)
    let identityValue = scale.sliderValue(for: 1.0)
    let largeValue = scale.sliderValue(for: 1.0e6)

    #expect(smallValue > 0.0)
    #expect(smallValue < identityValue)
    #expect(identityValue < largeValue)
    #expect(largeValue < 1.0)
    #expect(abs(scale.value(fromSliderValue: smallValue) - 1.0e-6) < 1.0e-18)
    #expect(abs(scale.value(fromSliderValue: identityValue) - 1.0) < 1.0e-12)
    #expect(abs(scale.value(fromSliderValue: largeValue) - 1.0e6) < 0.000_001)
}

@Test func workspaceScaleFactorSliderRangeIncludesLargeCurrentTransformScales() {
    let defaultRange = workspaceScaleFactorSliderRange(for: [1.0])
    let largeRange = workspaceScaleFactorSliderRange(for: [2.0e9])
    let tinyRange = workspaceScaleFactorSliderRange(for: [2.0e-10])

    #expect(defaultRange.lowerBound == 1.0e-9)
    #expect(defaultRange.upperBound == 1.0e9)
    #expect(largeRange.upperBound == 2.0e10)
    #expect(abs(tinyRange.lowerBound - 2.0e-11) < 1.0e-24)
}

@Test func workspaceLengthSliderMetersRangeUsesWorkspaceRulerSpan() {
    let microRange = workspaceLengthSliderMetersRange(
        for: 0.000_001,
        ruler: WorkspaceScalePreset.microFabrication.rulerConfiguration
    )
    let precisionRange = workspaceLengthSliderMetersRange(
        for: 0.001,
        ruler: WorkspaceScalePreset.precisionMechanical.rulerConfiguration
    )
    let siteRange = workspaceLengthSliderMetersRange(
        for: 1.0,
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )
    let regionalRange = workspaceLengthSliderMetersRange(
        for: 1.0,
        ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    )

    #expect(microRange == 0.0 ... 0.01)
    #expect(precisionRange == 0.0 ... 1.0)
    #expect(siteRange == 0.0 ... 100_000.0)
    #expect(regionalRange == 0.0 ... 1_000_000.0)
}

@Test func workspaceLengthInteractionSliderRangeKeepsValidationSeparateFromSliderScale() {
    let range = workspaceLengthInteractionSliderMetersRange(
        for: [0.001],
        fallbackRange: 0.0 ... 0.01,
        validationRange: ObjectPropertyDefinition.NumericRange(
            lowerBound: 0.0,
            upperBound: 1_000_000.0
        )
    )

    #expect(range == 0.0 ... 0.01)
}

@Test func workspaceLengthInteractionSliderRangeIncludesLargeCurrentValues() {
    let range = workspaceLengthInteractionSliderMetersRange(
        for: [25.0],
        fallbackRange: 0.0 ... 0.01,
        validationRange: ObjectPropertyDefinition.NumericRange(
            lowerBound: 0.0,
            upperBound: 1_000_000.0
        )
    )

    #expect(range == 0.0 ... 100.0)
}

@Test func workspaceLengthInteractionSliderRangeRespectsValidationUpperBound() {
    let range = workspaceLengthInteractionSliderMetersRange(
        for: [25.0],
        fallbackRange: 0.0 ... 1_000.0,
        validationRange: ObjectPropertyDefinition.NumericRange(
            lowerBound: 0.0,
            upperBound: 500.0
        )
    )

    #expect(range == 0.0 ... 500.0)
}

@Test func workspaceSignedLengthSliderMetersRangeUsesWorkspaceRulerSpan() {
    let precisionRange = workspaceSignedLengthSliderMetersRange(
        for: 0.001,
        ruler: WorkspaceScalePreset.precisionMechanical.rulerConfiguration
    )
    let siteRange = workspaceSignedLengthSliderMetersRange(
        for: 1.0,
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )
    let regionalRange = workspaceSignedLengthSliderMetersRange(
        for: 1.0,
        ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    )

    #expect(precisionRange == -1.0 ... 1.0)
    #expect(siteRange == -100_000.0 ... 100_000.0)
    #expect(regionalRange == -1_000_000.0 ... 1_000_000.0)
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

@Test func rulerScaleControlPresentsReadableMetricUnitsAcrossCADRange() {
    let visiblePresentation = RulerScaleControl.fieldPresentation(
        fromMeters: RulerConfiguration.visibleSpanMetersRange.upperBound,
        preferredUnit: .millimeter,
        for: .visible
    )
    let majorPresentation = RulerScaleControl.fieldPresentation(
        fromMeters: 1_000.0,
        preferredUnit: .millimeter,
        for: .major
    )
    let minorPresentation = RulerScaleControl.fieldPresentation(
        fromMeters: 0.000_25,
        preferredUnit: .meter,
        for: .minor
    )
    let centimeterPresentation = RulerScaleControl.fieldPresentation(
        fromMeters: 0.02,
        preferredUnit: .meter,
        for: .major
    )

    #expect(visiblePresentation.unit == .kilometer)
    #expect(visiblePresentation.value == 1_000.0)
    #expect(visiblePresentation.text == "1,000")
    #expect(majorPresentation.unit == .kilometer)
    #expect(majorPresentation.value == 1.0)
    #expect(centimeterPresentation.unit == .centimeter)
    #expect(centimeterPresentation.value == 2.0)
    #expect(minorPresentation.unit == .micrometer)
    #expect(minorPresentation.value == 250.0)
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

@Test func rulerScaleControlAcceptsExplicitUnitsIndependentOfDisplayUnit() {
    let kilometerMeters = RulerScaleControl.meters(
        fromFieldText: "1 km",
        unit: .millimeter,
        for: .visible
    )
    let micrometerMeters = RulerScaleControl.meters(
        fromFieldText: "250 um",
        unit: .meter,
        for: .minor
    )
    let clampedSiteMeters = RulerScaleControl.meters(
        fromFieldText: "2,000 km",
        unit: .millimeter,
        for: .visible
    )

    #expect(kilometerMeters == 1_000.0)
    #expect(micrometerMeters == 0.000_25)
    #expect(clampedSiteMeters == RulerConfiguration.visibleSpanMetersRange.upperBound)
}

@Test func workspaceScalePresetCompactWorkspaceTitlesStayConsistentAcrossChrome() {
    #expect(WorkspaceScalePreset.microFabrication.compactWorkspaceTitle == "Micro")
    #expect(WorkspaceScalePreset.precisionMechanical.compactWorkspaceTitle == "Precision")
    #expect(WorkspaceScalePreset.productDesign.compactWorkspaceTitle == "Product")
    #expect(WorkspaceScalePreset.roomInterior.compactWorkspaceTitle == "Room")
    #expect(WorkspaceScalePreset.architecture.compactWorkspaceTitle == "Arch")
    #expect(WorkspaceScalePreset.architectureImperial.compactWorkspaceTitle == "Arch ft")
    #expect(WorkspaceScalePreset.urbanPlanning.compactWorkspaceTitle == "Urban")
    #expect(WorkspaceScalePreset.sitePlanning.compactWorkspaceTitle == "Site")
    #expect(WorkspaceScalePreset.regionalPlanning.compactWorkspaceTitle == "Region")
    #expect(WorkspaceScalePreset.sitePlanningImperial.compactWorkspaceTitle == "Site ft")
}

@Test func workspaceScaleStatusSummaryReportsSitePlanningInKilometers() {
    let summary = WorkspaceScaleStatusSummary(
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )

    #expect(summary.compactTitle == "Site · 100 km")
    #expect(summary.presetTitle == "Site Planning")
    #expect(summary.useCaseTitle == "site, campus, and civil-scale coordination")
    #expect(summary.displayUnitTitle == "km")
    #expect(summary.minorStepTitle == "0.1 km")
    #expect(summary.majorStepTitle == "1 km")
    #expect(summary.visibleSpanTitle == "100 km")
    #expect(summary.comfortableModelSpanTitle == "1 km to 80 km")
    #expect(summary.detailTitle == "Site Planning, unit km, minor 0.1 km, major 1 km, visible 100 km")
    #expect(summary.accessibilityValue == summary.detailTitle)
    #expect(summary.smallerPreset == .urbanPlanning)
    #expect(summary.largerPreset == .regionalPlanning)
}

@Test func workspaceScaleStatusSummaryReportsUrbanPlanningInKilometers() {
    let summary = WorkspaceScaleStatusSummary(
        ruler: WorkspaceScalePreset.urbanPlanning.rulerConfiguration
    )

    #expect(summary.compactTitle == "Urban · 25 km")
    #expect(summary.presetTitle == "Urban Planning")
    #expect(summary.useCaseTitle == "urban districts, campuses, streetscape, and large site coordination")
    #expect(summary.displayUnitTitle == "km")
    #expect(summary.minorStepTitle == "10 m")
    #expect(summary.majorStepTitle == "0.1 km")
    #expect(summary.visibleSpanTitle == "25 km")
    #expect(summary.comfortableModelSpanTitle == "0.25 km to 20 km")
    #expect(summary.detailTitle == "Urban Planning, unit km, minor 10 m, major 0.1 km, visible 25 km")
    #expect(summary.accessibilityValue == summary.detailTitle)
    #expect(summary.smallerPreset == .architecture)
    #expect(summary.largerPreset == .sitePlanning)
}

@Test func workspaceScaleStatusSummaryReportsRegionalPlanningInKilometers() {
    let summary = WorkspaceScaleStatusSummary(
        ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    )

    #expect(summary.compactTitle == "Region · 1,000 km")
    #expect(summary.presetTitle == "Regional Planning")
    #expect(summary.useCaseTitle == "regional context, infrastructure corridors, and kilometer-scale terrain")
    #expect(summary.displayUnitTitle == "km")
    #expect(summary.minorStepTitle == "1 km")
    #expect(summary.majorStepTitle == "10 km")
    #expect(summary.visibleSpanTitle == "1,000 km")
    #expect(summary.comfortableModelSpanTitle == "10 km to 800 km")
    #expect(summary.detailTitle == "Regional Planning, unit km, minor 1 km, major 10 km, visible 1,000 km")
    #expect(summary.accessibilityValue == summary.detailTitle)
    #expect(summary.smallerPreset == .sitePlanning)
    #expect(summary.largerPreset == nil)
}

@Test func workspaceScaleStatusSummaryReportsReadableCustomScale() {
    let summary = WorkspaceScaleStatusSummary(
        ruler: RulerConfiguration(
            displayUnit: .millimeter,
            minorTickMeters: 0.000_001,
            majorTickMeters: 0.001,
            visibleSpanMeters: 1_000.0
        )
    )

    #expect(summary.compactTitle == "Custom · 1 km")
    #expect(summary.presetTitle == "Custom")
    #expect(summary.useCaseTitle == "custom ruler configuration")
    #expect(summary.minorStepTitle == "1 μm")
    #expect(summary.majorStepTitle == "1 mm")
    #expect(summary.visibleSpanTitle == "1 km")
    #expect(summary.comfortableModelSpanTitle == "10 m to 800 m")
    #expect(summary.smallerPreset == .roomInterior)
    #expect(summary.largerPreset == .architecture)
}

@Test func workspaceScaleStatusSummaryExposesPresetAdjustmentAffordances() {
    let product = WorkspaceScaleStatusSummary(
        ruler: WorkspaceScalePreset.productDesign.rulerConfiguration
    )
    let architecture = WorkspaceScaleStatusSummary(
        ruler: WorkspaceScalePreset.architecture.rulerConfiguration
    )
    let imperialSite = WorkspaceScaleStatusSummary(
        ruler: WorkspaceScalePreset.sitePlanningImperial.rulerConfiguration
    )

    #expect(product.smallerPreset == .precisionMechanical)
    #expect(product.largerPreset == .roomInterior)
    #expect(architecture.smallerPreset == .roomInterior)
    #expect(architecture.largerPreset == .urbanPlanning)
    #expect(imperialSite.smallerPreset == .architectureImperial)
    #expect(imperialSite.largerPreset == nil)
}

@Test func workspaceDocumentScalePresetOptionStatesExposeFullCADRange() throws {
    let options = workspaceDocumentScalePresetOptionStates(
        ruler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    )
    let micro = try #require(options.first { $0.preset == .microFabrication })
    let urban = try #require(options.first { $0.preset == .urbanPlanning })
    let regional = try #require(options.first { $0.preset == .regionalPlanning })
    let selected = try #require(options.first { $0.isSelected })

    #expect(options.map(\.preset) == WorkspaceScalePreset.profiles.map(\.preset))
    #expect(micro.visibleSpanTitle == "1 cm")
    #expect(micro.comfortableModelSpanTitle == "100 μm to 8 mm")
    #expect(urban.title == "Urban Planning")
    #expect(urban.menuTitle == "Urban Planning · 25 km")
    #expect(urban.visibleSpanTitle == "25 km")
    #expect(urban.comfortableModelSpanTitle == "0.25 km to 20 km")
    #expect(urban.accessibilityValue.contains("large site coordination"))
    #expect(regional.title == "Regional Planning")
    #expect(regional.menuTitle == "Regional Planning · 1,000 km")
    #expect(regional.visibleSpanTitle == "1,000 km")
    #expect(regional.comfortableModelSpanTitle == "10 km to 800 km")
    #expect(regional.minorStepTitle == "1 km")
    #expect(regional.majorStepTitle == "10 km")
    #expect(regional.displayUnitTitle == "km")
    #expect(regional.accessibilityValue.contains("kilometer-scale terrain"))
    #expect(selected.preset == .regionalPlanning)
}

@Test func workspaceDocumentScalePresetOptionStatesKeepRangeAvailableForCustomRulers() throws {
    let options = workspaceDocumentScalePresetOptionStates(
        ruler: RulerConfiguration(
            displayUnit: .millimeter,
            minorTickMeters: 0.000_001,
            majorTickMeters: 0.001,
            visibleSpanMeters: 1_000.0
        )
    )
    let regional = try #require(options.first { $0.preset == .regionalPlanning })

    #expect(options.count == WorkspaceScalePreset.profiles.count)
    #expect(!options.contains { $0.isSelected })
    #expect(regional.menuTitle == "Regional Planning · 1,000 km")
    #expect(regional.accessibilityValue.contains("comfortable model span 10 km to 800 km"))
}

@Test func workspaceDocumentScaleRecommendationStateReportsUseCaseAndComfortRanges() throws {
    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: MeasurementResult.Bounds(
            minX: 0.0,
            minY: 0.0,
            minZ: 0.0,
            maxX: 250_000.0,
            maxY: 120_000.0,
            maxZ: 1_000.0
        ),
        currentRuler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    ))

    let state = try #require(workspaceDocumentScaleRecommendationState(
        recommendation: recommendation
    ))

    #expect(state.reasonTitle == "Model exceeds ruler")
    #expect(state.presetTitle == "Regional Planning")
    #expect(state.useCaseTitle == "regional context, infrastructure corridors, and kilometer-scale terrain")
    #expect(state.modelSpanTitle == "250 km")
    #expect(state.currentComfortableModelSpanTitle == "1 km to 80 km")
    #expect(state.visibleSpanTitle == "1,000 km")
    #expect(state.recommendedComfortableModelSpanTitle == "10 km to 800 km")
    #expect(state.preset == .regionalPlanning)
    #expect(state.isActionable)
}

@Test func workspaceDocumentScaleRecommendationStateReportsActionlessScaleLimit() throws {
    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: MeasurementResult.Bounds(
            minX: 0.0,
            minY: 0.0,
            minZ: 0.0,
            maxX: 1_200_000.0,
            maxY: 400_000.0,
            maxZ: 1_000.0
        ),
        currentRuler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    ))

    let state = try #require(workspaceDocumentScaleRecommendationState(
        recommendation: recommendation
    ))

    #expect(state.reasonTitle == "Beyond scale range")
    #expect(state.presetTitle == "Regional Planning")
    #expect(state.modelSpanTitle == "1,200 km")
    #expect(state.recommendedComfortableModelSpanTitle == "10 km to 800 km")
    #expect(state.preset == .regionalPlanning)
    #expect(state.isActionable == false)
}

@Test func workspaceScaleFitPromptStateReportsCompactActionableRecommendation() throws {
    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: MeasurementResult.Bounds(
            minX: 0.0,
            minY: 0.0,
            minZ: 0.0,
            maxX: 25_000.0,
            maxY: 10_000.0,
            maxZ: 100.0
        ),
        currentRuler: RulerConfiguration.standard(for: .millimeter)
    ))

    let state = try #require(WorkspaceScaleFitPromptState(recommendation: recommendation))

    #expect(state.title == "Fit Site")
    #expect(state.isActionable)
    #expect(state.preset == .sitePlanning)
    #expect(state.help == "Fit workspace scale to Site Planning")
    #expect(state.accessibilityValue.contains("modelExceedsComfortableSpan"))
    #expect(state.accessibilityValue.contains("1 km to 80 km"))
}

@Test func workspaceScaleFitPromptStateReportsActionlessScaleLimit() throws {
    let recommendation = try #require(WorkspaceScaleRecommendationService().recommendation(
        for: MeasurementResult.Bounds(
            minX: 0.0,
            minY: 0.0,
            minZ: 0.0,
            maxX: 1_200_000.0,
            maxY: 400_000.0,
            maxZ: 1_000.0
        ),
        currentRuler: WorkspaceScalePreset.regionalPlanning.rulerConfiguration
    ))

    let state = try #require(WorkspaceScaleFitPromptState(recommendation: recommendation))

    #expect(state.title == "Scale Limit")
    #expect(state.isActionable == false)
    #expect(state.preset == .regionalPlanning)
    #expect(state.help == "Current model exceeds the supported workspace scale range")
    #expect(state.accessibilityValue.contains("modelExceedsSupportedScaleRange"))
    #expect(state.accessibilityValue.contains("10 km to 800 km"))
}

@Test func workspaceScaleFitPromptStateIgnoresMissingRecommendation() {
    #expect(WorkspaceScaleFitPromptState(recommendation: nil) == nil)
}

@Test func workspaceDocumentRecommendationStatesShareBoundsForScaleAndPrecision() throws {
    let states = workspaceDocumentRecommendationStates(
        bounds: MeasurementResult.Bounds(
            minX: 1.0e12,
            minY: 1.0e12,
            minZ: 0.0,
            maxX: 1.0e12 + 250_000.0,
            maxY: 1.0e12 + 120_000.0,
            maxZ: 1_000.0
        ),
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration,
        displayUnit: .kilometer
    )

    let scale = try #require(states.scale)
    let precision = try #require(states.precision)

    #expect(scale.reasonTitle == "Model exceeds ruler")
    #expect(scale.preset == .regionalPlanning)
    #expect(scale.modelSpanTitle == "250 km")
    #expect(precision.reasonTitle == "Coordinate resolution")
    #expect(precision.modelSpanTitle == "250 km")
    #expect(precision.translation == Vector3D(
        x: -(1.0e12 + 125_000.0),
        y: -(1.0e12 + 60_000.0),
        z: 0.0
    ))
}

@Test func workspaceDocumentPrecisionRecommendationStateFormatsRebaseAction() {
    let translation = Vector3D(x: -1_000_000.0, y: 500.0, z: 0.0)
    let report = WorkspacePrecisionReport(
        reason: .coordinateResolution,
        severity: .warning,
        originDistanceMeters: 1_000_000.0,
        maximumCoordinateMagnitudeMeters: 1_000_000.0,
        coordinateResolutionMeters: 0.001,
        precisionBudgetMeters: 0.0001,
        modelSpanMeters: 250.0,
        workspaceSpanMeters: 100_000.0,
        originToModelSpanRatio: 4_000.0,
        modelCenter: Point3D(x: 1_000_000.0, y: -500.0, z: 0.0),
        recommendedRebaseTranslation: translation
    )

    let state = workspaceDocumentPrecisionRecommendationState(
        report: report,
        displayUnit: .kilometer
    )

    #expect(state?.reasonTitle == "Coordinate resolution")
    #expect(state?.originDistanceTitle == "1,000 km")
    #expect(state?.modelSpanTitle == "0.25 km")
    #expect(state?.translationTitle == "x -1,000 km, y 0.5 km, z 0 km")
    #expect(state?.translation == translation)
}

@Test func workspaceDocumentPrecisionRecommendationStateRequiresRebaseTranslation() {
    let report = WorkspacePrecisionReport(
        reason: .farFromOrigin,
        severity: .info,
        originDistanceMeters: 10_000.0,
        maximumCoordinateMagnitudeMeters: 10_000.0,
        coordinateResolutionMeters: 0.000_001,
        precisionBudgetMeters: 0.0001,
        modelSpanMeters: 0.01,
        workspaceSpanMeters: 1.0,
        originToModelSpanRatio: 1_000_000.0,
        modelCenter: Point3D(x: 10_000.0, y: 0.0, z: 0.0),
        recommendedRebaseTranslation: nil
    )

    #expect(workspaceDocumentPrecisionRecommendationState(report: report, displayUnit: .meter) == nil)
}
