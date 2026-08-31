public struct SemanticProgramLimitPolicy: Sendable, Equatable, Hashable {
    public let maximumDecodedValueCount: Int
    public let maximumDecodedNestingDepth: Int
    public let maximumNodeCount: Int
    public let maximumEdgeCount: Int
    public let maximumParameterCount: Int
    public let maximumRequestedOutputCount: Int
    public let maximumLocalOutputReferenceCount: Int
    public let maximumExpressionCount: Int
    public let maximumExpressionDepth: Int
    public let maximumExpressionWork: UInt64
    public let maximumLoweredCommandCount: Int
    public let maximumExpandedSourceWork: UInt64
    public let maximumPreparedInputSlotCount: Int
    public let maximumPreparedOutputSlotCount: Int
    public let resultLimits: SemanticResultLimits

    public init(
        maximumDecodedValueCount: Int,
        maximumDecodedNestingDepth: Int,
        maximumNodeCount: Int,
        maximumEdgeCount: Int,
        maximumParameterCount: Int,
        maximumRequestedOutputCount: Int,
        maximumLocalOutputReferenceCount: Int,
        maximumExpressionCount: Int,
        maximumExpressionDepth: Int,
        maximumExpressionWork: UInt64,
        maximumLoweredCommandCount: Int,
        maximumExpandedSourceWork: UInt64,
        maximumPreparedInputSlotCount: Int,
        maximumPreparedOutputSlotCount: Int,
        resultLimits: SemanticResultLimits
    ) {
        self.maximumDecodedValueCount = maximumDecodedValueCount
        self.maximumDecodedNestingDepth = maximumDecodedNestingDepth
        self.maximumNodeCount = maximumNodeCount
        self.maximumEdgeCount = maximumEdgeCount
        self.maximumParameterCount = maximumParameterCount
        self.maximumRequestedOutputCount = maximumRequestedOutputCount
        self.maximumLocalOutputReferenceCount = maximumLocalOutputReferenceCount
        self.maximumExpressionCount = maximumExpressionCount
        self.maximumExpressionDepth = maximumExpressionDepth
        self.maximumExpressionWork = maximumExpressionWork
        self.maximumLoweredCommandCount = maximumLoweredCommandCount
        self.maximumExpandedSourceWork = maximumExpandedSourceWork
        self.maximumPreparedInputSlotCount = maximumPreparedInputSlotCount
        self.maximumPreparedOutputSlotCount = maximumPreparedOutputSlotCount
        self.resultLimits = resultLimits
    }
}
