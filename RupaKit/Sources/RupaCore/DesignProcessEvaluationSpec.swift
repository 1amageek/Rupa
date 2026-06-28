public struct DesignProcessEvaluationSpec: Codable, Equatable, Sendable {
    public var successCriteria: [String]
    public var diagnosticRequirements: [String]
    public var performanceBudget: String
    public var requiredEvidence: [String]

    public init(
        successCriteria: [String] = [],
        diagnosticRequirements: [String] = [],
        performanceBudget: String = "",
        requiredEvidence: [String] = []
    ) {
        self.successCriteria = successCriteria
        self.diagnosticRequirements = diagnosticRequirements
        self.performanceBudget = performanceBudget
        self.requiredEvidence = requiredEvidence
    }
}
