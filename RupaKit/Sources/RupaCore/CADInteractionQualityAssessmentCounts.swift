public struct CADInteractionQualityAssessmentCounts: Codable, Equatable, Sendable {
    public var entryCount: Int
    public var verifiedCount: Int
    public var implementedCount: Int
    public var partialCount: Int
    public var plannedCount: Int
    public var missingCount: Int
    public var blockingGapCount: Int

    public init(
        entryCount: Int = 0,
        verifiedCount: Int = 0,
        implementedCount: Int = 0,
        partialCount: Int = 0,
        plannedCount: Int = 0,
        missingCount: Int = 0,
        blockingGapCount: Int = 0
    ) {
        self.entryCount = entryCount
        self.verifiedCount = verifiedCount
        self.implementedCount = implementedCount
        self.partialCount = partialCount
        self.plannedCount = plannedCount
        self.missingCount = missingCount
        self.blockingGapCount = blockingGapCount
    }
}
