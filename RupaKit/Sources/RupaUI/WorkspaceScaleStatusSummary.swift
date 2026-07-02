import RupaCore

struct WorkspaceScaleStatusSummary: Equatable, Sendable {
    var compactTitle: String
    var presetTitle: String
    var useCaseTitle: String
    var displayUnitTitle: String
    var visibleSpanTitle: String
    var comfortableModelSpanTitle: String
    var minorStepTitle: String
    var majorStepTitle: String
    var detailTitle: String
    var accessibilityValue: String
    var smallerPreset: WorkspaceScalePreset?
    var largerPreset: WorkspaceScalePreset?

    init(ruler: RulerConfiguration) {
        let normalized = ruler.normalizedForWorkspaceScale()
        let matchedPreset = WorkspaceScalePreset.matching(normalized)
        let preferredUnit = normalized.displayUnit
        let matchedProfile = matchedPreset?.profile
        let visibleSpanTitle = Self.lengthTitle(
            fromMeters: normalized.visibleSpanMeters,
            preferredUnit: preferredUnit
        )
        let presetTitle = matchedPreset?.title ?? "Custom"
        let useCaseTitle = matchedProfile?.useCaseTitle ?? "custom ruler configuration"
        let comfortableModelSpanTitle = matchedProfile?.comfortableModelSpanTitle
            ?? Self.customComfortableModelSpanTitle(
                ruler: normalized,
                preferredUnit: preferredUnit
            )
        let displayUnitTitle = preferredUnit.symbol
        let minorStepTitle = Self.lengthTitle(
            fromMeters: normalized.minorTickMeters,
            preferredUnit: preferredUnit
        )
        let majorStepTitle = Self.lengthTitle(
            fromMeters: normalized.majorTickMeters,
            preferredUnit: preferredUnit
        )
        self.compactTitle = "\(matchedPreset?.compactWorkspaceTitle ?? "Custom") · \(visibleSpanTitle)"
        self.presetTitle = presetTitle
        self.useCaseTitle = useCaseTitle
        self.displayUnitTitle = displayUnitTitle
        self.visibleSpanTitle = visibleSpanTitle
        self.comfortableModelSpanTitle = comfortableModelSpanTitle
        self.minorStepTitle = minorStepTitle
        self.majorStepTitle = majorStepTitle
        self.detailTitle = "\(presetTitle), unit \(displayUnitTitle), minor \(minorStepTitle), major \(majorStepTitle), visible \(visibleSpanTitle)"
        self.accessibilityValue = detailTitle
        self.smallerPreset = Self.adjacentPreset(
            from: normalized,
            matchedPreset: matchedPreset,
            direction: .smaller
        )
        self.largerPreset = Self.adjacentPreset(
            from: normalized,
            matchedPreset: matchedPreset,
            direction: .larger
        )
    }

    private static func lengthTitle(
        fromMeters meters: Double,
        preferredUnit: LengthDisplayUnit
    ) -> String {
        let unit = preferredUnit.readableUnit(forMeters: meters)
        return WorkspaceInspectorNumberText.lengthString(
            fromMeters: meters,
            unit: unit
        )
    }

    private static func customComfortableModelSpanTitle(
        ruler: RulerConfiguration,
        preferredUnit: LengthDisplayUnit
    ) -> String {
        let lower = ruler.visibleSpanMeters * WorkspaceScalePreset.minimumComfortableModelSpanRatio
        let upper = ruler.visibleSpanMeters * WorkspaceScalePreset.maximumComfortableModelSpanRatio
        let lowerTitle = lengthTitle(fromMeters: lower, preferredUnit: preferredUnit)
        let upperTitle = lengthTitle(fromMeters: upper, preferredUnit: preferredUnit)
        return "\(lowerTitle) to \(upperTitle)"
    }

    private enum ScaleDirection {
        case smaller
        case larger
    }

    private static func adjacentPreset(
        from ruler: RulerConfiguration,
        matchedPreset: WorkspaceScalePreset?,
        direction: ScaleDirection
    ) -> WorkspaceScalePreset? {
        let ladder = presetLadder(for: ruler.displayUnit)
        if let matchedPreset,
           let index = ladder.firstIndex(of: matchedPreset) {
            switch direction {
            case .smaller:
                guard index > ladder.startIndex else {
                    return nil
                }
                return ladder[ladder.index(before: index)]
            case .larger:
                let nextIndex = ladder.index(after: index)
                guard nextIndex < ladder.endIndex else {
                    return nil
                }
                return ladder[nextIndex]
            }
        }

        let visibleSpan = ruler.visibleSpanMeters
        switch direction {
        case .smaller:
            return ladder.last { preset in
                preset.rulerConfiguration.visibleSpanMeters < visibleSpan
            }
        case .larger:
            return ladder.first { preset in
                preset.rulerConfiguration.visibleSpanMeters > visibleSpan
            }
        }
    }

    private static func presetLadder(for displayUnit: LengthDisplayUnit) -> [WorkspaceScalePreset] {
        if displayUnit.isMetric {
            return [
                .microFabrication,
                .precisionMechanical,
                .productDesign,
                .roomInterior,
                .architecture,
                .sitePlanning,
                .regionalPlanning,
            ]
        }
        return [
            .architectureImperial,
            .sitePlanningImperial,
        ]
    }
}
