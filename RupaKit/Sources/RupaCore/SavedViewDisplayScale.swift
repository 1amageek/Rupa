import RupaCoreTypes

public struct SavedViewDisplayScale: Codable, Hashable, Sendable {
    public var displayUnit: LengthDisplayUnit
    public var minorTickMeters: Double
    public var majorTickMeters: Double
    public var visibleSpanMeters: Double
    public var scaleBarLengthMeters: Double
    public var matchedPreset: WorkspaceScalePreset?

    public init(
        displayUnit: LengthDisplayUnit,
        minorTickMeters: Double,
        majorTickMeters: Double,
        visibleSpanMeters: Double,
        scaleBarLengthMeters: Double,
        matchedPreset: WorkspaceScalePreset? = nil
    ) {
        self.displayUnit = displayUnit
        self.minorTickMeters = minorTickMeters
        self.majorTickMeters = majorTickMeters
        self.visibleSpanMeters = visibleSpanMeters
        self.scaleBarLengthMeters = scaleBarLengthMeters
        self.matchedPreset = matchedPreset
    }

    public init(
        ruler: RulerConfiguration,
        scaleBarLengthMeters: Double? = nil
    ) {
        let normalized = ruler.normalizedForWorkspaceScale()
        self.init(
            displayUnit: normalized.displayUnit,
            minorTickMeters: normalized.minorTickMeters,
            majorTickMeters: normalized.majorTickMeters,
            visibleSpanMeters: normalized.visibleSpanMeters,
            scaleBarLengthMeters: scaleBarLengthMeters ?? normalized.majorTickMeters,
            matchedPreset: WorkspaceScalePreset.matching(normalized)
        )
    }

    public var rulerConfiguration: RulerConfiguration {
        RulerConfiguration(
            displayUnit: displayUnit,
            minorTickMeters: minorTickMeters,
            majorTickMeters: majorTickMeters,
            visibleSpanMeters: visibleSpanMeters
        )
    }

    public func validate() throws {
        try rulerConfiguration.validate()
        guard scaleBarLengthMeters.isFinite,
              scaleBarLengthMeters > 0.0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view scale bar length must be finite and positive."
            )
        }
        if let matchedPreset {
            guard WorkspaceScalePreset.matching(rulerConfiguration) == matchedPreset else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view matched scale preset must match the saved ruler scale."
                )
            }
        }
    }
}
