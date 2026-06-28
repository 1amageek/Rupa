public struct DesignProcessCaseGroup: Codable, Equatable, Sendable {
    public var kind: DesignProcessCaseGroupKind
    public var cases: [DesignProcessCase]

    public init(
        kind: DesignProcessCaseGroupKind,
        cases: [DesignProcessCase] = []
    ) {
        self.kind = kind
        self.cases = cases
    }
}
