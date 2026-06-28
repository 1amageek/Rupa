public struct DesignProcessResolution: Codable, Equatable, Sendable {
    public var selectedRouteIDs: [String]
    public var decisions: [DesignProcessDecisionRecord]
    public var openQuestions: [String]

    public init(
        selectedRouteIDs: [String] = [],
        decisions: [DesignProcessDecisionRecord] = [],
        openQuestions: [String] = []
    ) {
        self.selectedRouteIDs = selectedRouteIDs
        self.decisions = decisions
        self.openQuestions = openQuestions
    }
}
