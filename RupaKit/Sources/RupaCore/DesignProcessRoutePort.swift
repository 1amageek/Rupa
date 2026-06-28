public struct DesignProcessRoutePort: Codable, Equatable, Sendable {
    public var kind: DesignProcessRoutePortKind
    public var identifier: String
    public var title: String

    public init(
        kind: DesignProcessRoutePortKind,
        identifier: String,
        title: String
    ) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
    }
}
