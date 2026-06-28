public struct DesignProcessConfidence: Codable, Equatable, Sendable {
    public var evidenceFreshness: Double
    public var testCoverage: Double
    public var performanceCoverage: Double
    public var missingChannelPenalty: Double
    public var calibrationState: DesignProcessCalibrationState
    public var calibrationAnchors: [DesignProcessCalibrationAnchor]
    public var performanceMeasurements: [DesignProcessPerformanceMeasurement]
    public var notes: [String]

    public init(
        evidenceFreshness: Double,
        testCoverage: Double,
        performanceCoverage: Double,
        missingChannelPenalty: Double,
        calibrationState: DesignProcessCalibrationState,
        calibrationAnchors: [DesignProcessCalibrationAnchor] = [],
        performanceMeasurements: [DesignProcessPerformanceMeasurement] = [],
        notes: [String] = []
    ) {
        self.evidenceFreshness = evidenceFreshness
        self.testCoverage = testCoverage
        self.performanceCoverage = performanceCoverage
        self.missingChannelPenalty = missingChannelPenalty
        self.calibrationState = calibrationState
        self.calibrationAnchors = calibrationAnchors
        self.performanceMeasurements = performanceMeasurements
        self.notes = notes
    }

    public var score: Double {
        max(
            0.0,
            min(
                1.0,
                (
                    evidenceFreshness * 0.2
                    + testCoverage * 0.25
                    + effectivePerformanceCoverage * 0.2
                    + effectiveCalibrationCoverage * 0.25
                    + calibrationAnchorCoverage * 0.1
                )
                - missingChannelPenalty * 0.2
            )
        )
    }

    private var effectivePerformanceCoverage: Double {
        guard !performanceMeasurements.isEmpty else {
            return performanceCoverage
        }
        let measuredCoverage = performanceMeasurements.reduce(0.0) { result, measurement in
            switch measurement.status {
            case .withinBudget:
                result + 1.0
            case .missingBudget:
                result + 0.25
            case .exceedsBudget, .unmeasured:
                result
            }
        } / Double(performanceMeasurements.count)
        return min(performanceCoverage, measuredCoverage)
    }

    private var effectiveCalibrationCoverage: Double {
        guard !calibrationAnchors.isEmpty else {
            return calibrationState.multiplier
        }
        let anchorCoverage = calibrationAnchors.reduce(0.0) { result, anchor in
            result + anchor.state.multiplier
        } / Double(calibrationAnchors.count)
        return min(calibrationState.multiplier, anchorCoverage)
    }

    private var calibrationAnchorCoverage: Double {
        min(1.0, Double(calibrationAnchors.count) / 3.0)
    }
}
