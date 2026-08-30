import Foundation

public struct CADBenchmarkReport: Codable, Equatable, Sendable {
    public static let schemaVersion = "t12.report.v1"
    public static let maximumEncodedBytes = 16_384

    public let schemaVersion: String
    public let status: CADBenchmarkRunStatus
    public let manifestSchemaVersion: String
    public let catalogVersion: String
    public let manifestDigest: String
    public let expectationDigest: String
    public let capabilityAvailabilityDigest: String
    public let expectedExecutionBaselineDigest: String
    public let observedExecutionBaselineDigest: String
    public let baselineDrifts: [CADBenchmarkBaselineDrift]
    public let results: [CADCaseResult]
    public let score: CADBenchmarkScore

    init(
        attempt: CADBenchmarkReferenceRunAttempt,
        capabilityBaseline: CADCapabilityAvailabilityBaseline,
        expectedBaseline: CADExecutionRegressionBaseline,
        observedBaseline: CADExecutionRegressionBaseline,
        baselineDrifts: [CADBenchmarkBaselineDrift]
    ) throws {
        try attempt.validate()
        try capabilityBaseline.validate()
        try expectedBaseline.validate()
        try observedBaseline.validate()
        let expectation = try CADInternalCatalogStore.expectationContract()
        try expectation.validate()
        let canonicalResults = observedBaseline.records.map { record in
            CADCaseResult(
                id: record.caseID,
                category: record.category,
                outcome: record.outcome,
                capabilityDecisionCorrect: record.capabilityDecisionCorrect,
                durationMilliseconds: nil
            )
        }
        let orderedDrifts = CADBenchmarkBaselineDrift.allCases.filter(baselineDrifts.contains)
        self.schemaVersion = Self.schemaVersion
        self.status = orderedDrifts.isEmpty ? .valid : .baselineDrift
        self.manifestSchemaVersion = attempt.manifest.schema
        self.catalogVersion = attempt.manifest.catalog
        self.manifestDigest = attempt.manifest.digest
        self.expectationDigest = expectation.digest
        self.capabilityAvailabilityDigest = capabilityBaseline.digest
        self.expectedExecutionBaselineDigest = expectedBaseline.digest
        self.observedExecutionBaselineDigest = observedBaseline.digest
        self.baselineDrifts = orderedDrifts
        self.results = canonicalResults
        self.score = try CADBenchmarkScore(results: canonicalResults)
        try validate()
    }

    public func canonicalJSON() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw CADBenchmarkBaselineError.encodedArtifactTooLarge(
                limit: Self.maximumEncodedBytes,
                actual: data.count
            )
        }
        return data
    }

    func validate() throws {
        let manifest = try CADBenchmarkCatalog().manifest
        guard schemaVersion == Self.schemaVersion,
              manifestSchemaVersion == CADBenchmarkManifest.schemaVersion,
              catalogVersion == CADBenchmarkManifest.catalogVersion,
              [manifestDigest, expectationDigest, capabilityAvailabilityDigest,
               expectedExecutionBaselineDigest, observedExecutionBaselineDigest]
                .allSatisfy(Self.isDigest),
              baselineDrifts == CADBenchmarkBaselineDrift.allCases.filter(baselineDrifts.contains),
              Set(baselineDrifts).count == baselineDrifts.count,
              (status == .valid) == baselineDrifts.isEmpty,
              status != .invalid,
              results.count == 100,
              results.map(\.id) == manifest.orderedCaseIDs,
              results.allSatisfy({ $0.durationMilliseconds == nil }),
              score.totalCases == 100,
              score.realizedCases == 95,
              score.expectedUnsupportedCases == 5,
              score.supportedCases == 95,
              score.supportedRealizedCases == 95,
              score.capabilityDecisionTotal == 100,
              score.capabilityDecisionsCorrect == 100,
              status == .baselineDrift || expectedExecutionBaselineDigest == observedExecutionBaselineDigest,
              status == .valid || expectedExecutionBaselineDigest != observedExecutionBaselineDigest else {
            throw CADBenchmarkBaselineError.invalidReport
        }
        for result in results {
            try result.validate()
        }
        guard try CADBenchmarkScore(results: results) == score else {
            throw CADBenchmarkBaselineError.invalidReport
        }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains($0) }
    }
}
