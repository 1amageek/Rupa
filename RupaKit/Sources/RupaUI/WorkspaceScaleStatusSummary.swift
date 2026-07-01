import RupaCore

struct WorkspaceScaleStatusSummary: Equatable, Sendable {
    var compactTitle: String
    var presetTitle: String
    var displayUnitTitle: String
    var visibleSpanTitle: String
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
        let visibleSpanTitle = Self.lengthTitle(
            fromMeters: normalized.visibleSpanMeters,
            preferredUnit: preferredUnit
        )
        let presetTitle = matchedPreset?.title ?? "Custom"
        let displayUnitTitle = preferredUnit.symbol
        let minorStepTitle = Self.lengthTitle(
            fromMeters: normalized.minorTickMeters,
            preferredUnit: preferredUnit
        )
        let majorStepTitle = Self.lengthTitle(
            fromMeters: normalized.majorTickMeters,
            preferredUnit: preferredUnit
        )
        self.compactTitle = "\(Self.compactPresetTitle(matchedPreset)) · \(visibleSpanTitle)"
        self.presetTitle = presetTitle
        self.displayUnitTitle = displayUnitTitle
        self.visibleSpanTitle = visibleSpanTitle
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

    private static func compactPresetTitle(_ preset: WorkspaceScalePreset?) -> String {
        switch preset {
        case .microFabrication:
            "Micro"
        case .precisionMechanical:
            "Precision"
        case .productDesign:
            "Product"
        case .roomInterior:
            "Room"
        case .architecture:
            "Arch"
        case .architectureImperial:
            "Arch ft"
        case .sitePlanning:
            "Site"
        case .sitePlanningImperial:
            "Site ft"
        case nil:
            "Custom"
        }
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
            ]
        }
        return [
            .architectureImperial,
            .sitePlanningImperial,
        ]
    }
}
