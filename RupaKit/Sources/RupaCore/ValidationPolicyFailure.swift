public struct ValidationPolicyFailure: Codable, Equatable, Sendable {
    public var ruleID: String
    public var reasons: [ValidationPolicyFailureReason]

    public init(
        ruleID: String,
        reasons: [ValidationPolicyFailureReason]
    ) {
        self.ruleID = ruleID
        self.reasons = reasons
    }
}
