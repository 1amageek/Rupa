public struct CADBenchmarkScore: Codable, Equatable, Sendable {
    public let totalCases: Int
    public let realizedCases: Int
    public let expectedUnsupportedCases: Int
    public let capabilityDecisionsCorrect: Int
    public let categoryRealizedCounts: [CADCategoryCount]

    public init(results: [CADCaseResult]) throws {
        var caseIDs = Set<CADBenchmarkCaseID>()
        for result in results {
            try result.validate()
            guard caseIDs.insert(result.id).inserted else {
                throw CADBenchmarkError.duplicateCaseID(result.id.rawValue)
            }
        }
        totalCases = results.count
        realizedCases = results.filter(\.realized).count
        expectedUnsupportedCases = results.filter { $0.outcome == .expectedUnsupported }.count
        capabilityDecisionsCorrect = results.compactMap(\.capabilityDecisionCorrect).filter { $0 }.count
        categoryRealizedCounts = CADBenchmarkCategory.allCases.sorted { $0.rawValue < $1.rawValue }.map { category in
            CADCategoryCount(
                category: category,
                count: results.filter { $0.category == category && $0.realized }.count
            )
        }
    }
}
