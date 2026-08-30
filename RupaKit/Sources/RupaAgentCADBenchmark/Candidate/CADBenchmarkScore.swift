public struct CADBenchmarkScore: Codable, Equatable, Sendable {
    public let totalCases: Int
    public let realizedCases: Int
    public let expectedUnsupportedCases: Int
    public let supportedCases: Int
    public let supportedRealizedCases: Int
    public let capabilityDecisionTotal: Int
    public let capabilityDecisionsCorrect: Int
    public let categoryRealizedCounts: [CADCategoryCount]

    public init(results: [CADCaseResult]) throws {
        let manifest = try CADBenchmarkCatalog().manifest
        let orderedResults = results.sorted { $0.id < $1.id }
        guard orderedResults.map(\.id) == manifest.orderedCaseIDs else {
            throw CADBenchmarkError.catalogDrift(
                expected: "exactly 100 manifest case results",
                actual: "partial, duplicate, extra, or mismatched score input"
            )
        }
        var caseIDs = Set<CADBenchmarkCaseID>()
        for result in orderedResults {
            try result.validate()
            guard caseIDs.insert(result.id).inserted else {
                throw CADBenchmarkError.duplicateCaseID(result.id.rawValue)
            }
            guard result.capabilityDecisionCorrect != nil else {
                throw CADBenchmarkError.invalidInput(
                    caseID: result.id.rawValue,
                    reason: "A canonical score requires a capability decision for every case."
                )
            }
        }
        totalCases = 100
        realizedCases = orderedResults.filter(\.realized).count
        expectedUnsupportedCases = orderedResults.filter {
            $0.outcome == .expectedUnsupported
        }.count
        supportedCases = totalCases - expectedUnsupportedCases
        supportedRealizedCases = orderedResults.filter(\.realized).count
        capabilityDecisionTotal = 100
        capabilityDecisionsCorrect = orderedResults.compactMap(\.capabilityDecisionCorrect)
            .filter { $0 }.count
        categoryRealizedCounts = CADBenchmarkCategory.allCases.sorted { $0.rawValue < $1.rawValue }.map { category in
            CADCategoryCount(
                category: category,
                count: orderedResults.filter { $0.category == category && $0.realized }.count
            )
        }
    }
}
