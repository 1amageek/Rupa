public struct DesignProcessFlowPortRequirement: Codable, Equatable, Sendable {
    public var nodeID: String
    public var portID: String
    public var connection: DesignProcessFlowPortConnection
    public var reason: String

    public init(
        nodeID: String,
        portID: String,
        connection: DesignProcessFlowPortConnection,
        reason: String
    ) {
        self.nodeID = nodeID
        self.portID = portID
        self.connection = connection
        self.reason = reason
    }
}
