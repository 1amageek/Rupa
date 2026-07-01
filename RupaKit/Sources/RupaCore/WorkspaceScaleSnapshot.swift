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

    private enum CodingKeys: String, CodingKey {
        case displayUnit
        case displayUnitSymbol
        case minorTickMeters
        case majorTickMeters
        case visibleSpanMeters
        case minorTickDisplayValue
        case majorTickDisplayValue
        case visibleSpanDisplayValue
        case matchedPreset
        case matchedPresetTitle
    }

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let displayUnit = try container.decode(LengthDisplayUnit.self, forKey: .displayUnit)
        let minorTickMeters = try container.decode(Double.self, forKey: .minorTickMeters)
        let majorTickMeters = try container.decode(Double.self, forKey: .majorTickMeters)
        let visibleSpanMeters = try container.decode(Double.self, forKey: .visibleSpanMeters)
        self.init(
            displayUnit: displayUnit,
            displayUnitSymbol: try container.decode(String.self, forKey: .displayUnitSymbol),
            minorTickMeters: minorTickMeters,
            majorTickMeters: majorTickMeters,
            visibleSpanMeters: visibleSpanMeters,
            minorTickDisplayValue: try container.decodeIfPresent(
                Double.self,
                forKey: .minorTickDisplayValue
            ),
            majorTickDisplayValue: try container.decodeIfPresent(
                Double.self,
                forKey: .majorTickDisplayValue
            ),
            visibleSpanDisplayValue: try container.decodeIfPresent(
                Double.self,
                forKey: .visibleSpanDisplayValue
            ),
            matchedPreset: try container.decodeIfPresent(
                WorkspaceScalePreset.self,
                forKey: .matchedPreset
            ),
            matchedPresetTitle: try container.decodeIfPresent(
                String.self,
                forKey: .matchedPresetTitle
            )
        )
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
        let minorTick = LengthDisplayText.lengthString(
            fromMeters: minorTickMeters,
            unit: displayUnit,
            usesArchitecturalFeet: false
        )
        let majorTick = LengthDisplayText.lengthString(
            fromMeters: majorTickMeters,
            unit: displayUnit,
            usesArchitecturalFeet: false
        )
        let visibleSpan = LengthDisplayText.lengthString(
            fromMeters: visibleSpanMeters,
            unit: displayUnit,
            usesArchitecturalFeet: false
        )
        return "Workspace scale \(presetTitle), unit \(displayUnitSymbol), minor \(minorTick), major \(majorTick), visible span \(visibleSpan)."
    }
}
