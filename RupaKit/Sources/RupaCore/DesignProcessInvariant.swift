public struct DesignProcessInvariant: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var requiredLayer: DesignProcessLayer
    public var verification: String

    public init(
        id: String,
        title: String,
        requiredLayer: DesignProcessLayer,
        verification: String
    ) {
        self.id = id
        self.title = title
        self.requiredLayer = requiredLayer
        self.verification = verification
    }
}
