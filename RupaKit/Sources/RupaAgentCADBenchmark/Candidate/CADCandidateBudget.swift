public struct CADCandidateBudget: Codable, Equatable, Hashable, Sendable {
    public let maximumRounds: Int
    public let maximumActions: Int
    public let maximumReadRecords: Int

    public init(maximumRounds: Int = 16, maximumActions: Int = 32, maximumReadRecords: Int = 64) {
        self.maximumRounds = maximumRounds
        self.maximumActions = maximumActions
        self.maximumReadRecords = maximumReadRecords
    }

    public func validate() throws {
        guard maximumRounds > 0, maximumActions > 0, maximumReadRecords >= 0 else {
            throw CADBenchmarkError.invalidBudget("Budget values must be positive, except read records may be zero.")
        }
        guard maximumActions >= maximumRounds else {
            throw CADBenchmarkError.invalidBudget("Action budget must cover every candidate round.")
        }
    }
}
