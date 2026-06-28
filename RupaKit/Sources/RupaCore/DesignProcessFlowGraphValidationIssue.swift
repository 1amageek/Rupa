public struct DesignProcessFlowGraphValidationIssue: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case duplicateNode
        case duplicatePort
        case missingRequiredNode
        case missingRequiredPort
        case danglingEdgeSourceNode
        case danglingEdgeTargetNode
        case danglingEdgeSourcePort
        case danglingEdgeTargetPort
        case floatingRequiredOutput
        case unreachableRequiredInput
        case disconnectedRequiredPort
        case deadEndNode
    }

    public var kind: Kind
    public var nodeID: String?
    public var portID: String?
    public var edgeID: String?
    public var message: String

    public init(
        kind: Kind,
        nodeID: String? = nil,
        portID: String? = nil,
        edgeID: String? = nil,
        message: String
    ) {
        self.kind = kind
        self.nodeID = nodeID
        self.portID = portID
        self.edgeID = edgeID
        self.message = message
    }
}
