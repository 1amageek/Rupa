public struct DesignProcessFlowGraphValidationResult: Codable, Equatable, Sendable {
    public var issues: [DesignProcessFlowGraphValidationIssue]

    public init(issues: [DesignProcessFlowGraphValidationIssue] = []) {
        self.issues = issues
    }

    public var isValid: Bool {
        issues.isEmpty
    }
}
