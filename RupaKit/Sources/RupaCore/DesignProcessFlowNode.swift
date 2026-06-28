public struct DesignProcessFlowNode: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var layer: DesignProcessLayer
    public var ports: [DesignProcessFlowPort]

    public init(
        id: String,
        title: String,
        layer: DesignProcessLayer,
        ports: [DesignProcessFlowPort] = []
    ) {
        self.id = id
        self.title = title
        self.layer = layer
        self.ports = ports
    }
}
