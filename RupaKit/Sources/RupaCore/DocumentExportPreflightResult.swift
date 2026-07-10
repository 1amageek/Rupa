public struct DocumentExportPreflightResult: Codable, Equatable, Sendable {
    public var policyEvaluation: ValidationPolicyEvaluation
    public var diagnostics: [EditorDiagnostic]
    public var findings: [ValidationFinding]
    public var blockingReasons: [String]

    public init(
        policyEvaluation: ValidationPolicyEvaluation,
        diagnostics: [EditorDiagnostic],
        findings: [ValidationFinding],
        blockingReasons: [String]
    ) {
        self.policyEvaluation = policyEvaluation
        self.diagnostics = diagnostics
        self.findings = findings
        self.blockingReasons = blockingReasons
    }

    public var isAllowed: Bool {
        policyEvaluation.decision == .allow && blockingReasons.isEmpty
    }
}
