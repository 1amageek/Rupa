public struct DesignProcessIntent: Codable, Equatable, Sendable {
    public var capabilityID: String
    public var title: String
    public var outcome: String
    public var area: CADInteractionQualityArea
    public var sourceOfTruth: DesignProcessLayer
    public var referenceSources: [String]

    public init(
        capabilityID: String,
        title: String,
        outcome: String,
        area: CADInteractionQualityArea,
        sourceOfTruth: DesignProcessLayer,
        referenceSources: [String] = []
    ) {
        self.capabilityID = capabilityID
        self.title = title
        self.outcome = outcome
        self.area = area
        self.sourceOfTruth = sourceOfTruth
        self.referenceSources = referenceSources
    }
}
