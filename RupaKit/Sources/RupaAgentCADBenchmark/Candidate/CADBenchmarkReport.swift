public struct CADBenchmarkReport: Codable, Equatable, Sendable {
    public let manifest: CADBenchmarkManifest
    public let status: CADBenchmarkRunStatus
    public let results: [CADCaseResult]
    public let score: CADBenchmarkScore

    public init(
        manifest: CADBenchmarkManifest,
        status: CADBenchmarkRunStatus,
        results: [CADCaseResult]
    ) throws {
        try manifest.validate()
        let sortedResults = results.sorted { $0.id < $1.id }
        guard sortedResults.map(\.id) == manifest.orderedCaseIDs else {
            throw CADBenchmarkError.catalogDrift(
                expected: "one result for every manifest case",
                actual: "report case IDs do not match manifest"
            )
        }
        for result in sortedResults {
            try result.validate()
        }
        let score = try CADBenchmarkScore(results: sortedResults)
        self.manifest = manifest
        self.status = status
        self.results = sortedResults
        self.score = score
    }
}
