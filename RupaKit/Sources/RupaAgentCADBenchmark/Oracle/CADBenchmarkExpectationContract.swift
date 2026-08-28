import Foundation
import SwiftCAD
import RupaCoreTypes

struct CADBenchmarkExpectationContract: Codable, Equatable, Sendable {
    static let schemaVersion = "t12.expectation.v3"
    static let expectationVersion = "t12.expectation-contract.v3"
    static let capabilityClassificationVersion = "t12.capability-classification.v1"
    static let capabilityBaselineContractVersion = "t12.capability-baseline.v1"

    let schemaVersion: String
    let expectationVersion: String
    let expectationDigest: String
    let capabilityClassificationVersion: String
    let capabilityClassificationDigest: String
    let capabilityBaselineContractVersion: String
    let tolerancePolicyVersion: String
    let tolerance: ToleranceSnapshot
    let capabilityBaseline: CapabilityBaseline
    let entries: [ExpectationEntry]

    var digest: String {
        expectationDigest
    }

    init(entries: [CADCatalogEntry]) throws {
        let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: .standard)
        self.schemaVersion = Self.schemaVersion
        self.expectationVersion = Self.expectationVersion
        self.capabilityClassificationVersion = Self.capabilityClassificationVersion
        self.capabilityBaselineContractVersion = Self.capabilityBaselineContractVersion
        self.tolerancePolicyVersion = CADBenchmarkTolerancePolicy.version
        self.tolerance = ToleranceSnapshot(policy: tolerance)

        let sortedEntries = entries.sorted { $0.challenge.id < $1.challenge.id }
        self.entries = sortedEntries.map {
            ExpectationEntry(
                id: $0.challenge.id,
                expected: $0.expected,
                expectationDigest: $0.expectationDigest,
                requiresAnalyticSurface: $0.requiresAnalyticSurface,
                outputRoles: $0.challenge.outputRoles
            )
        }
        self.capabilityBaseline = try CapabilityBaseline(entries: sortedEntries)
        self.capabilityClassificationDigest = try Self.digest(
            CapabilityClassificationPayload(records: capabilityBaseline.records)
        )

        let payload = Payload(
            schemaVersion: schemaVersion,
            expectationVersion: expectationVersion,
            capabilityClassificationVersion: capabilityClassificationVersion,
            capabilityClassificationDigest: capabilityClassificationDigest,
            capabilityBaselineContractVersion: capabilityBaselineContractVersion,
            tolerancePolicyVersion: tolerancePolicyVersion,
            tolerance: self.tolerance,
            capabilityBaseline: capabilityBaseline,
            entries: self.entries
        )
        self.expectationDigest = try Self.digest(payload)
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              expectationVersion == Self.expectationVersion,
              capabilityClassificationVersion == Self.capabilityClassificationVersion,
              capabilityBaselineContractVersion == Self.capabilityBaselineContractVersion,
              tolerancePolicyVersion == CADBenchmarkTolerancePolicy.version,
              entries.count == 100 else {
            throw CADBenchmarkError.catalogDrift(
                expected: "current expectation contract schema and 100 entries",
                actual: "stale or incomplete expectation contract"
            )
        }
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: ModelingTolerance(
                distance: tolerance.distance,
                angle: tolerance.angle,
                relative: tolerance.relative
            )
        )
        let sortedEntries = entries.sorted { $0.id < $1.id }
        guard entries.map(\.id) == sortedEntries.map(\.id),
              Set(entries.map(\.id)).count == entries.count else {
            throw CADBenchmarkError.catalogDrift(
                expected: "unique lexically ordered expectation IDs",
                actual: "unordered or duplicate expectation IDs"
            )
        }
        let payload = Payload(
            schemaVersion: schemaVersion,
            expectationVersion: expectationVersion,
            capabilityClassificationVersion: capabilityClassificationVersion,
            capabilityClassificationDigest: capabilityClassificationDigest,
            capabilityBaselineContractVersion: capabilityBaselineContractVersion,
            tolerancePolicyVersion: tolerancePolicyVersion,
            tolerance: ToleranceSnapshot(policy: tolerance),
            capabilityBaseline: capabilityBaseline,
            entries: entries
        )
        let recomputed = try Self.digest(payload)
        guard recomputed == expectationDigest else {
            throw CADBenchmarkError.catalogDrift(expected: expectationDigest, actual: recomputed)
        }
        let expectedClassificationDigest = try Self.digest(
            CapabilityClassificationPayload(records: capabilityBaseline.records)
        )
        guard capabilityClassificationDigest == expectedClassificationDigest else {
            throw CADBenchmarkError.catalogDrift(
                expected: capabilityClassificationDigest,
                actual: expectedClassificationDigest
            )
        }
        try capabilityBaseline.validate()
    }

    private static func digest<Value: Encodable>(_ payload: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return StableDigest.sha256Hex(for: try encoder.encode(payload))
    }

    struct ToleranceSnapshot: Codable, Equatable, Sendable {
        let distance: Double
        let angle: Double
        let relative: Double

        init(policy: CADBenchmarkTolerancePolicy) {
            distance = policy.modelingTolerance.distance
            angle = policy.modelingTolerance.angle
            relative = policy.modelingTolerance.relative
        }
    }

    struct ExpectationEntry: Codable, Equatable, Sendable {
        let id: CADBenchmarkCaseID
        let expected: CADExpectedGeometry
        let expectationDigest: String
        let requiresAnalyticSurface: Bool
        let outputRoles: [CADOutputRole]
    }

    struct CapabilityBaseline: Codable, Equatable, Sendable {
        let version: String
        let records: [CapabilityRecord]
        let digest: String

        init(entries: [CADCatalogEntry]) throws {
            let records = Dictionary(grouping: entries, by: {
                "\($0.challenge.requiredCapability.id)@\($0.challenge.requiredCapability.version)"
            }).compactMap { _, grouped -> CapabilityRecord? in
                guard let first = grouped.first else { return nil }
                let classification: CADCapabilityClassification = first.requiresAnalyticSurface
                    ? .analyticSphere
                    : .standardGeometry
                return CapabilityRecord(
                    id: first.challenge.requiredCapability.id,
                    version: first.challenge.requiredCapability.version,
                    classification: classification
                )
            }.sorted {
                ($0.id, $0.version) < ($1.id, $1.version)
            }
            self.version = CADBenchmarkExpectationContract.capabilityBaselineContractVersion
            self.records = records
            let payload = CapabilityPayload(version: version, records: records)
            self.digest = try Self.digest(payload)
        }

        func validate() throws {
            guard version == CADBenchmarkExpectationContract.capabilityBaselineContractVersion else {
                throw CADBenchmarkError.catalogDrift(
                    expected: CADBenchmarkExpectationContract.capabilityBaselineContractVersion,
                    actual: version
                )
            }
            let sortedRecords = records.sorted { ($0.id, $0.version) < ($1.id, $1.version) }
            guard records == sortedRecords else {
                throw CADBenchmarkError.catalogDrift(
                    expected: "lexically ordered capability records",
                    actual: "unordered capability records"
                )
            }
            let payload = CapabilityPayload(version: version, records: records)
            let recomputed = try Self.digest(payload)
            guard recomputed == digest else {
                throw CADBenchmarkError.catalogDrift(expected: digest, actual: recomputed)
            }
        }

        private static func digest(_ payload: CapabilityPayload) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return StableDigest.sha256Hex(for: try encoder.encode(payload))
        }
    }

    struct CapabilityRecord: Codable, Equatable, Sendable {
        let id: String
        let version: String
        let classification: CADCapabilityClassification
    }

    private struct Payload: Codable {
        let schemaVersion: String
        let expectationVersion: String
        let capabilityClassificationVersion: String
        let capabilityClassificationDigest: String
        let capabilityBaselineContractVersion: String
        let tolerancePolicyVersion: String
        let tolerance: ToleranceSnapshot
        let capabilityBaseline: CapabilityBaseline
        let entries: [ExpectationEntry]
    }

    private struct CapabilityClassificationPayload: Codable {
        let records: [CapabilityRecord]
    }

    private struct CapabilityPayload: Codable {
        let version: String
        let records: [CapabilityRecord]
    }
}
