import RupaCore

public struct ViewportPatternArrayPreview: Equatable, Sendable {
    public struct Output: Equatable, Sendable {
        public var index: Int
        public var itemIDs: [String]
        public var isSelected: Bool

        public init(
            index: Int,
            itemIDs: [String],
            isSelected: Bool
        ) {
            self.index = index
            self.itemIDs = itemIDs
            self.isSelected = isSelected
        }
    }

    public var sourceID: PatternArraySourceID
    public var distributionKind: PatternArraySummary.DistributionKind
    public var outputMode: PatternArrayOutputMode
    public var outputCount: Int
    public var outputs: [Output]

    public init(
        sourceID: PatternArraySourceID,
        distributionKind: PatternArraySummary.DistributionKind,
        outputMode: PatternArrayOutputMode,
        outputCount: Int,
        outputs: [Output]
    ) {
        self.sourceID = sourceID
        self.distributionKind = distributionKind
        self.outputMode = outputMode
        self.outputCount = outputCount
        self.outputs = outputs
    }
}
