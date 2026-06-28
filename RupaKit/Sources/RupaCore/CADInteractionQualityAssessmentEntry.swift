public struct CADInteractionQualityAssessmentEntry: Codable, Equatable, Sendable {
    public var area: CADInteractionQualityArea
    public var workflow: String
    public var referenceSources: [String]
    public var currentRating: CADInteractionQualityRating
    public var gateAssessments: [CADInteractionQualityGateAssessment]
    public var evidence: [CADInteractionQualityEvidence]
    public var openWork: [String]
    public var nextRequiredResult: String
    public var designProcessPacket: DesignProcessPacket

    public init(
        area: CADInteractionQualityArea,
        workflow: String,
        referenceSources: [String],
        currentRating: CADInteractionQualityRating,
        gateAssessments: [CADInteractionQualityGateAssessment],
        evidence: [CADInteractionQualityEvidence] = [],
        openWork: [String] = [],
        nextRequiredResult: String,
        designProcessPacket: DesignProcessPacket
    ) {
        self.area = area
        self.workflow = workflow
        self.referenceSources = referenceSources
        self.currentRating = currentRating
        self.gateAssessments = gateAssessments
        self.evidence = evidence
        self.openWork = openWork
        self.nextRequiredResult = nextRequiredResult
        self.designProcessPacket = designProcessPacket
    }

    public var weakestRating: CADInteractionQualityRating {
        gateAssessments
            .map(\.rating)
            .min { lhs, rhs in lhs.score < rhs.score }
            ?? .missing
    }
}
