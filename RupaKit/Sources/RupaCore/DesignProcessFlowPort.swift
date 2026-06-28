public struct DesignProcessFlowPort: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var direction: DesignProcessFlowPortDirection
    public var notes: [String]

    public init(
        id: String,
        title: String,
        direction: DesignProcessFlowPortDirection,
        notes: [String] = []
    ) {
        self.id = id
        self.title = title
        self.direction = direction
        self.notes = notes
    }
}
