public struct DesignProcessConfidence: Codable, Equatable, Sendable {
    public var evidenceFreshness: Double
    public var testCoverage: Double
    public var performanceCoverage: Double
    public var missingChannelPenalty: Double
    public var calibrationState: DesignProcessCalibrationState
    public var notes: [String]

    public init(
        evidenceFreshness: Double,
        testCoverage: Double,
        performanceCoverage: Double,
        missingChannelPenalty: Double,
        calibrationState: DesignProcessCalibrationState,
        notes: [String] = []
    ) {
        self.evidenceFreshness = evidenceFreshness
        self.testCoverage = testCoverage
        self.performanceCoverage = performanceCoverage
        self.missingChannelPenalty = missingChannelPenalty
        self.calibrationState = calibrationState
        self.notes = notes
    }

    public var score: Double {
        max(
            0.0,
            min(
                1.0,
                (
                    evidenceFreshness * 0.25
                    + testCoverage * 0.3
                    + performanceCoverage * 0.2
                    + calibrationState.multiplier * 0.25
                )
                - missingChannelPenalty * 0.2
            )
        )
    }
}
