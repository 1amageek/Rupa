public struct SemanticCompilationTelemetry: Sendable, Equatable, Hashable {
    public let decodedValueCount: Int
    public let decodedNestingDepth: Int
    public let nodeCount: Int
    public let edgeCount: Int
    public let parameterCount: Int
    public let requestedOutputCount: Int
    public let localOutputReferenceCount: Int
    public let expressionCount: Int
    public let expressionDepth: Int
    public let expressionWork: UInt64
    public let loweredCommandCount: Int
    public let expandedSourceWork: UInt64

    init(
        decodedValueCount: Int,
        decodedNestingDepth: Int,
        nodeCount: Int,
        edgeCount: Int,
        parameterCount: Int,
        requestedOutputCount: Int,
        localOutputReferenceCount: Int,
        expressionCount: Int,
        expressionDepth: Int,
        expressionWork: UInt64,
        loweredCommandCount: Int,
        expandedSourceWork: UInt64
    ) {
        self.decodedValueCount = decodedValueCount
        self.decodedNestingDepth = decodedNestingDepth
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.parameterCount = parameterCount
        self.requestedOutputCount = requestedOutputCount
        self.localOutputReferenceCount = localOutputReferenceCount
        self.expressionCount = expressionCount
        self.expressionDepth = expressionDepth
        self.expressionWork = expressionWork
        self.loweredCommandCount = loweredCommandCount
        self.expandedSourceWork = expandedSourceWork
    }
}
