import RupaCoreTypes

public struct WorkspaceScaleSnapshot: Codable, Equatable, Sendable {
    public var displayUnit: LengthDisplayUnit
    public var displayUnitSymbol: String
    public var minorTickMeters: Double
    public var majorTickMeters: Double
    public var visibleSpanMeters: Double
    public var minorTickDisplayValue: Double
    public var majorTickDisplayValue: Double
    public var visibleSpanDisplayValue: Double
    public var matchedPreset: WorkspaceScalePreset?
    public var matchedPresetTitle: String?

    public init(
        displayUnit: LengthDisplayUnit,
        displayUnitSymbol: String,
        minorTickMeters: Double,
        majorTickMeters: Double,
        visibleSpanMeters: Double,
        minorTickDisplayValue: Double? = nil,
        majorTickDisplayValue: Double? = nil,
        visibleSpanDisplayValue: Double? = nil,
        matchedPreset: WorkspaceScalePreset?,
        matchedPresetTitle: String?
    ) {
        self.displayUnit = displayUnit
        self.displayUnitSymbol = displayUnitSymbol
        self.minorTickMeters = minorTickMeters
        self.majorTickMeters = majorTickMeters
        self.visibleSpanMeters = visibleSpanMeters
        self.minorTickDisplayValue = minorTickDisplayValue
            ?? displayUnit.value(fromMeters: minorTickMeters)
        self.majorTickDisplayValue = majorTickDisplayValue
            ?? displayUnit.value(fromMeters: majorTickMeters)
        self.visibleSpanDisplayValue = visibleSpanDisplayValue
            ?? displayUnit.value(fromMeters: visibleSpanMeters)
        self.matchedPreset = matchedPreset
        self.matchedPresetTitle = matchedPresetTitle
    }

    public init(ruler: RulerConfiguration) {
        let normalized = ruler.normalizedForWorkspaceScale()
        let preset = WorkspaceScalePreset.matching(normalized)
        self.init(
            displayUnit: normalized.displayUnit,
            displayUnitSymbol: normalized.displayUnit.symbol,
            minorTickMeters: normalized.minorTickMeters,
            majorTickMeters: normalized.majorTickMeters,
            visibleSpanMeters: normalized.visibleSpanMeters,
            matchedPreset: preset,
            matchedPresetTitle: preset?.title
        )
    }

    public var summary: String {
        let presetTitle = matchedPresetTitle ?? "Custom"
        let minorTick = MeasurementDisplayNumberText.lengthString(
            fromMeters: minorTickMeters,
            unit: displayUnit
        )
        let majorTick = MeasurementDisplayNumberText.lengthString(
            fromMeters: majorTickMeters,
            unit: displayUnit
        )
        let visibleSpan = MeasurementDisplayNumberText.lengthString(
            fromMeters: visibleSpanMeters,
            unit: displayUnit
        )
        return "Workspace scale \(presetTitle), unit \(displayUnitSymbol), minor \(minorTick), major \(majorTick), visible span \(visibleSpan)."
    }
}
