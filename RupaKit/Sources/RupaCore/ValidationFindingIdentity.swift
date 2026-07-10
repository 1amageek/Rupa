public struct ValidationFindingIdentity: Codable, Hashable, Sendable {
    public var ruleID: String
    public var ruleVersion: String
    public var providerID: String
    public var providerVersion: String
    public var outcome: ValidationOutcome
    public var diagnosticCode: String
    public var subjects: [ValidationSubjectReference]

    public init(
        ruleID: String,
        ruleVersion: String,
        providerID: String,
        providerVersion: String,
        outcome: ValidationOutcome,
        diagnosticCode: String,
        subjects: [ValidationSubjectReference]
    ) {
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.providerID = providerID
        self.providerVersion = providerVersion
        self.outcome = outcome
        self.diagnosticCode = diagnosticCode
        self.subjects = subjects
    }
}
