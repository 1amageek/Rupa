public struct DesignProcessConstraintBinding: Codable, Equatable, Sendable {
    public var validationRules: [String]
    public var invariants: [DesignProcessInvariant]
    public var sourceRewriteLimits: [String]
    public var topologyIdentityRules: [String]

    public init(
        validationRules: [String] = [],
        invariants: [DesignProcessInvariant] = [],
        sourceRewriteLimits: [String] = [],
        topologyIdentityRules: [String] = []
    ) {
        self.validationRules = validationRules
        self.invariants = invariants
        self.sourceRewriteLimits = sourceRewriteLimits
        self.topologyIdentityRules = topologyIdentityRules
    }
}
