public struct CADCaseResult: Codable, Equatable, Sendable {
    public let id: CADBenchmarkCaseID
    public let category: CADBenchmarkCategory
    public let outcome: CADCaseOutcome
    public let capabilityDecisionCorrect: Bool?
    public let durationMilliseconds: Double?

    public init(
        id: CADBenchmarkCaseID,
        category: CADBenchmarkCategory,
        outcome: CADCaseOutcome,
        capabilityDecisionCorrect: Bool? = nil,
        durationMilliseconds: Double? = nil
    ) {
        self.id = id
        self.category = category
        self.outcome = outcome
        self.capabilityDecisionCorrect = capabilityDecisionCorrect
        self.durationMilliseconds = durationMilliseconds
    }

    public var realized: Bool {
        outcome == .realized
    }

    public func validate() throws {
        try id.validate()
        guard id.category == category else {
            throw CADBenchmarkError.invalidInput(
                caseID: id.rawValue,
                reason: "Case result category does not match its case ID."
            )
        }
        if let durationMilliseconds {
            guard durationMilliseconds.isFinite, durationMilliseconds >= 0.0 else {
                throw CADBenchmarkError.invalidInput(
                    caseID: id.rawValue,
                    reason: "Case result duration must be finite and non-negative."
                )
            }
        }
    }
}
