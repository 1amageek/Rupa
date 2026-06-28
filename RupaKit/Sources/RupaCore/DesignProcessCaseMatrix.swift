public struct DesignProcessCaseMatrix: Codable, Equatable, Sendable {
    public var supported: DesignProcessCaseGroup
    public var boundary: DesignProcessCaseGroup
    public var degenerate: DesignProcessCaseGroup
    public var rejected: DesignProcessCaseGroup
    public var missing: DesignProcessCaseGroup
    public var performance: DesignProcessCaseGroup

    public init(
        supported: DesignProcessCaseGroup = DesignProcessCaseGroup(kind: .supported),
        boundary: DesignProcessCaseGroup = DesignProcessCaseGroup(kind: .boundary),
        degenerate: DesignProcessCaseGroup = DesignProcessCaseGroup(kind: .degenerate),
        rejected: DesignProcessCaseGroup = DesignProcessCaseGroup(kind: .rejected),
        missing: DesignProcessCaseGroup = DesignProcessCaseGroup(kind: .missing),
        performance: DesignProcessCaseGroup = DesignProcessCaseGroup(kind: .performance)
    ) {
        self.supported = supported
        self.boundary = boundary
        self.degenerate = degenerate
        self.rejected = rejected
        self.missing = missing
        self.performance = performance
    }

    public var cases: [DesignProcessCase] {
        supported.cases + boundary.cases + degenerate.cases + rejected.cases + missing.cases + performance.cases
    }
}
