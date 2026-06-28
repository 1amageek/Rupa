public struct DesignProcessFlowEdge: Codable, Equatable, Sendable {
    public var id: String
    public var sourceNodeID: String
    public var sourcePortID: String
    public var targetNodeID: String
    public var targetPortID: String
    public var label: String?
    public var evidence: [String]

    public init(
        id: String,
        sourceNodeID: String,
        sourcePortID: String,
        targetNodeID: String,
        targetPortID: String,
        label: String? = nil,
        evidence: [String] = []
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.targetPortID = targetPortID
        self.label = label
        self.evidence = evidence
    }
}
