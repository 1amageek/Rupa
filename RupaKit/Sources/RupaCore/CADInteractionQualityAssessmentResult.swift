public struct CADInteractionQualityAssessmentResult: Codable, Equatable, Sendable {
    public var referenceDate: String
    public var scoringModel: String
    public var score: Double
    public var counts: CADInteractionQualityAssessmentCounts
    public var entries: [CADInteractionQualityAssessmentEntry]

    public init(
        referenceDate: String,
        scoringModel: String,
        score: Double,
        counts: CADInteractionQualityAssessmentCounts,
        entries: [CADInteractionQualityAssessmentEntry]
    ) {
        self.referenceDate = referenceDate
        self.scoringModel = scoringModel
        self.score = score
        self.counts = counts
        self.entries = entries
    }
}
