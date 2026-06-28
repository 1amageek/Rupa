public struct DesignProcessRouteMatrix: Codable, Equatable, Sendable {
    public var requiredPorts: [DesignProcessRoutePortKind]
    public var routes: [DesignProcessRoute]

    public init(
        requiredPorts: [DesignProcessRoutePortKind] = [],
        routes: [DesignProcessRoute] = []
    ) {
        self.requiredPorts = requiredPorts
        self.routes = routes
    }

    public func missingRequiredPortKinds() -> [DesignProcessRoutePortKind] {
        let coveredKinds = Set(routes.flatMap { [$0.source.kind, $0.target.kind] })
        return requiredPorts.filter { !coveredKinds.contains($0) }
    }
}
