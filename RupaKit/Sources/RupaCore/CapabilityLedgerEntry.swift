public struct CapabilityLedgerEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var category: CapabilityLedgerCategory
    public var area: CADInteractionQualityArea?
    public var title: String
    public var currentRating: CADInteractionQualityRating
    public var gateAssessments: [CADInteractionQualityGateAssessment]
    public var evidence: [CADInteractionQualityEvidence]
    public var openWork: [String]
    public var nextRequiredResult: String

    public init(
        id: String,
        category: CapabilityLedgerCategory = .universalCAD,
        area: CADInteractionQualityArea? = nil,
        title: String,
        currentRating: CADInteractionQualityRating,
        gateAssessments: [CADInteractionQualityGateAssessment],
        evidence: [CADInteractionQualityEvidence],
        openWork: [String],
        nextRequiredResult: String
    ) {
        self.id = id
        self.category = category
        self.area = area
        self.title = title
        self.currentRating = currentRating
        self.gateAssessments = gateAssessments
        self.evidence = evidence
        self.openWork = openWork
        self.nextRequiredResult = nextRequiredResult
    }

    public init(assessmentEntry: CADInteractionQualityAssessmentEntry) {
        self.init(
            id: assessmentEntry.area.rawValue,
            category: .universalCAD,
            area: assessmentEntry.area,
            title: assessmentEntry.workflow,
            currentRating: assessmentEntry.currentRating,
            gateAssessments: assessmentEntry.gateAssessments,
            evidence: assessmentEntry.evidence,
            openWork: assessmentEntry.openWork,
            nextRequiredResult: assessmentEntry.nextRequiredResult
        )
    }

    public var isAccepted: Bool {
        currentRating == .verified
            && gateAssessments.allSatisfy { $0.rating == .verified }
    }

    public var blockingGateAssessments: [CADInteractionQualityGateAssessment] {
        gateAssessments.filter {
            $0.rating.score < CADInteractionQualityRating.implemented.score
        }
    }
}
