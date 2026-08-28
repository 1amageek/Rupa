public struct CADCandidateContext: Codable, Equatable, Sendable {
    public let challenge: CADChallenge
    public let capabilities: CADCapabilitySnapshot
    public let priorResults: [CADCandidateStepResult]
    public let remainingRounds: Int
    public let remainingActions: Int

    public init(
        challenge: CADChallenge,
        capabilities: CADCapabilitySnapshot,
        priorResults: [CADCandidateStepResult] = [],
        remainingRounds: Int,
        remainingActions: Int
    ) {
        self.challenge = challenge
        self.capabilities = capabilities
        self.priorResults = priorResults
        self.remainingRounds = remainingRounds
        self.remainingActions = remainingActions
    }

    public func validate() throws {
        try challenge.validate()
        try capabilities.validate()
        guard remainingRounds >= 0, remainingActions >= 0 else {
            throw CADBenchmarkError.invalidBudget("Remaining candidate budget cannot be negative.")
        }
        for result in priorResults {
            try result.validate()
        }
    }
}
