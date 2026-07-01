import RupaCore

struct WorkspaceScaleStatusSummary: Equatable, Sendable {
    var compactTitle: String
    var presetTitle: String
    var visibleSpanTitle: String
    var minorStepTitle: String
    var majorStepTitle: String

    init(ruler: RulerConfiguration) {
        let normalized = ruler.normalizedForWorkspaceScale()
        let matchedPreset = WorkspaceScalePreset.matching(normalized)
        let preferredUnit = normalized.displayUnit
        let visibleSpanTitle = Self.lengthTitle(
            fromMeters: normalized.visibleSpanMeters,
            preferredUnit: preferredUnit
        )
        let presetTitle = matchedPreset?.title ?? "Custom"
        self.compactTitle = "\(Self.compactPresetTitle(matchedPreset)) · \(visibleSpanTitle)"
        self.presetTitle = presetTitle
        self.visibleSpanTitle = visibleSpanTitle
        self.minorStepTitle = Self.lengthTitle(
            fromMeters: normalized.minorTickMeters,
            preferredUnit: preferredUnit
        )
        self.majorStepTitle = Self.lengthTitle(
            fromMeters: normalized.majorTickMeters,
            preferredUnit: preferredUnit
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
}
