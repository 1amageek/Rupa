import Foundation
import RupaCoreTypes

struct CADExecutionRegressionBaseline: Codable, Equatable, Sendable {
    static let schemaVersion = "t12.execution-regression.v1"

    let schemaVersion: String
    let environment: CADBenchmarkEnvironmentFingerprint
    let records: [CADCaseRegressionRecord]
    let digest: String

    init(
        attempt: CADBenchmarkReferenceRunAttempt,
        capabilityBaseline: CADCapabilityAvailabilityBaseline
    ) throws {
        try attempt.validate()
        try capabilityBaseline.validate()
        let expectation = try CADInternalCatalogStore.expectationContract()
        try expectation.validate()
        let environment = try CADBenchmarkEnvironmentFingerprint(
            manifestDigest: attempt.manifest.digest,
            expectationDigest: expectation.digest,
            capabilityAvailabilityDigest: capabilityBaseline.digest
        )
        self.schemaVersion = Self.schemaVersion
        self.environment = environment
        self.records = attempt.regressionRecords
        self.digest = try Self.computeDigest(Payload(
            schemaVersion: Self.schemaVersion,
            environment: environment,
            records: records
        ))
        try validate()
    }

    init(
        environment: CADBenchmarkEnvironmentFingerprint,
        records: [CADCaseRegressionRecord]
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.environment = environment
        self.records = records
        self.digest = try Self.computeDigest(Payload(
            schemaVersion: Self.schemaVersion,
            environment: environment,
            records: records
        ))
        try validate()
    }

    func validate() throws {
        try environment.validate()
        guard schemaVersion == Self.schemaVersion,
              records.count == 100,
              records.map(\.caseID) == records.map(\.caseID).sorted(),
              Set(records.map(\.caseID)).count == 100 else {
            throw CADBenchmarkBaselineError.invalidExecutionBaseline
        }
        for record in records {
            try record.validate()
            let expectedOutcome: CADCaseOutcome = record.category == .sphere
                ? .expectedUnsupported
                : .realized
            let expectedDisposition: CADCaseRegressionRecord.OracleDisposition =
                record.category == .sphere ? .expectedUnsupported : .accepted
            guard record.outcome == expectedOutcome,
                  record.capabilityDecisionCorrect,
                  record.oracleDisposition == expectedDisposition else {
                throw CADBenchmarkBaselineError.invalidExecutionBaseline
            }
        }
        let recomputed = try Self.computeDigest(Payload(
            schemaVersion: schemaVersion,
            environment: environment,
            records: records
        ))
        guard digest == recomputed else {
            throw CADBenchmarkBaselineError.invalidExecutionBaseline
        }
    }

    func differences(from expected: Self) throws -> [CADBenchmarkBaselineDrift] {
        try validate()
        try expected.validate()
        var differences = environment.differences(from: expected.environment)
        if records != expected.records {
            differences.append(.executionRecords)
        }
        return CADBenchmarkBaselineDrift.allCases.filter(differences.contains)
    }

    private struct Payload: Codable {
        let schemaVersion: String
        let environment: CADBenchmarkEnvironmentFingerprint
        let records: [CADCaseRegressionRecord]
    }

    private static func computeDigest(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return StableDigest.sha256Hex(for: try encoder.encode(payload))
    }
}
