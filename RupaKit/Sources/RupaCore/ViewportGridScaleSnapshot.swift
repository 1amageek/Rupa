import RupaCoreTypes

public struct ViewportGridScaleSnapshot: Codable, Equatable, Sendable {
    public struct Length: Codable, Equatable, Sendable {
        public let meters: Double
        public let displayValue: Double
        public let displayUnit: LengthDisplayUnit
        public let displayUnitSymbol: String
        public let text: String

        public init(
            meters: Double,
            preferredUnit: LengthDisplayUnit
        ) {
            let displayUnit = preferredUnit.readableUnit(forMeters: meters)
            self.meters = meters
            self.displayValue = displayUnit.value(fromMeters: meters)
            self.displayUnit = displayUnit
            self.displayUnitSymbol = displayUnit.symbol
            self.text = LengthDisplayText.lengthString(
                fromMeters: meters,
                unit: displayUnit
            )
        }
    }

    public let visualSpacingMode: ViewportGridVisualSpacingMode
    public let displayUnit: LengthDisplayUnit
    public let displayUnitSymbol: String
    public let snapStep: Length
    public let configuredMinorStep: Length
    public let configuredMajorStep: Length
    public let workspaceSpan: Length

    public init(
        ruler: RulerConfiguration,
        settings: ViewportGridSettings
    ) {
        let normalized = ruler.normalizedForWorkspaceScale()
        self.visualSpacingMode = settings.visualSpacingMode
        self.displayUnit = normalized.displayUnit
        self.displayUnitSymbol = normalized.displayUnit.symbol
        self.snapStep = Length(
            meters: normalized.minorTickMeters,
            preferredUnit: normalized.displayUnit
        )
        self.configuredMinorStep = Length(
            meters: normalized.minorTickMeters,
            preferredUnit: normalized.displayUnit
        )
        self.configuredMajorStep = Length(
            meters: normalized.majorTickMeters,
            preferredUnit: normalized.displayUnit
        )
        self.workspaceSpan = Length(
            meters: normalized.visibleSpanMeters,
            preferredUnit: normalized.displayUnit
        )
    }

    public var summary: String {
        "Viewport grid mode \(visualSpacingMode.rawValue), snap \(snapStep.text), configured minor \(configuredMinorStep.text), configured major \(configuredMajorStep.text), workspace span \(workspaceSpan.text)."
    }
}
