public struct CADInteractionQualityGateAssessment: Codable, Equatable, Sendable {
    public var gate: CADInteractionQualityGate
    public var rating: CADInteractionQualityRating
    public var evidence: [String]
    public var openWork: [String]

    public init(
        gate: CADInteractionQualityGate,
        rating: CADInteractionQualityRating,
        evidence: [String] = [],
        openWork: [String] = []
    ) {
        self.gate = gate
        self.rating = rating
        self.evidence = evidence
        self.openWork = openWork
    }
}
