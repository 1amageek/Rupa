import RupaCoreTypes

public struct WorkspaceInteractionScaleSnapshot: Codable, Equatable, Sendable {
    public struct Length: Codable, Equatable, Sendable {
        public let meters: Double
        public let displayValue: Double
        public let displayUnit: LengthDisplayUnit
        public let displayUnitSymbol: String

        public init(
            meters: Double,
            preferredUnit: LengthDisplayUnit
        ) {
            let displayUnit = Self.displayUnit(
                forMeters: meters,
                preferredUnit: preferredUnit
            )
            self.meters = meters
            self.displayValue = displayUnit.value(fromMeters: meters)
            self.displayUnit = displayUnit
            self.displayUnitSymbol = displayUnit.symbol
        }

        private static func displayUnit(
            forMeters meters: Double,
            preferredUnit: LengthDisplayUnit
        ) -> LengthDisplayUnit {
            preferredUnit.readableUnit(forMeters: meters)
        }
    }

    public struct LengthRange: Codable, Equatable, Sendable {
        public let lower: Length
        public let upper: Length

        public init(
            meters: ClosedRange<Double>,
            preferredUnit: LengthDisplayUnit
        ) {
            self.lower = Length(
                meters: meters.lowerBound,
                preferredUnit: preferredUnit
            )
            self.upper = Length(
                meters: meters.upperBound,
                preferredUnit: preferredUnit
            )
        }
    }

    public let displayUnit: LengthDisplayUnit
    public let displayUnitSymbol: String
    public let operationStep: Length
    public let slotWidth: Length
    public let surfaceFrameTangentialMove: Length
    public let surfaceFrameNormalMove: Length
    public let sketchRebuildTolerance: Length
    public let sketchRebuildToleranceRange: LengthRange

    public init(
        defaults: WorkspaceInteractionScaleDefaults,
        displayUnit: LengthDisplayUnit
    ) {
        self.displayUnit = displayUnit
        self.displayUnitSymbol = displayUnit.symbol
        self.operationStep = Length(
            meters: defaults.operationStepMeters,
            preferredUnit: displayUnit
        )
        self.slotWidth = Length(
            meters: defaults.slotWidthMeters,
            preferredUnit: displayUnit
        )
        self.surfaceFrameTangentialMove = Length(
            meters: defaults.surfaceFrameTangentialMoveMeters,
            preferredUnit: displayUnit
        )
        self.surfaceFrameNormalMove = Length(
            meters: defaults.surfaceFrameNormalMoveMeters,
            preferredUnit: displayUnit
        )
        self.sketchRebuildTolerance = Length(
            meters: defaults.sketchRebuildToleranceMeters,
            preferredUnit: displayUnit
        )
        self.sketchRebuildToleranceRange = LengthRange(
            meters: defaults.sketchRebuildToleranceRange,
            preferredUnit: displayUnit
        )
    }

    public init(ruler: RulerConfiguration) {
        let normalized = ruler.normalizedForWorkspaceScale()
        self.init(
            defaults: WorkspaceInteractionScaleDefaults(ruler: normalized),
            displayUnit: normalized.displayUnit
        )
    }

    public var summary: String {
        "Workspace interaction scale unit \(displayUnitSymbol), operation step \(operationStep.displayValue) \(operationStep.displayUnitSymbol), slot width \(slotWidth.displayValue) \(slotWidth.displayUnitSymbol), sketch rebuild tolerance \(sketchRebuildTolerance.displayValue) \(sketchRebuildTolerance.displayUnitSymbol)."
    }
}
