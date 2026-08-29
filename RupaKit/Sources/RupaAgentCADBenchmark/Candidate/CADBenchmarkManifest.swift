import Foundation
import RupaCoreTypes

public struct CADBenchmarkManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = "t12.manifest.v2"
    public static let catalogVersion = "t12.catalog.v5"
    public static let tolerancePolicyVersion = "t12.tolerance.v1"

    public let schema: String
    public let catalog: String
    public let tolerancePolicy: String
    public let orderedCaseIDs: [CADBenchmarkCaseID]
    public let categoryCounts: [CADCategoryCount]
    public let challengeInputDigest: String
    public let digest: String

    public init(
        schema: String = CADBenchmarkManifest.schemaVersion,
        catalog: String = CADBenchmarkManifest.catalogVersion,
        tolerancePolicy: String = CADBenchmarkManifest.tolerancePolicyVersion,
        orderedCaseIDs: [CADBenchmarkCaseID],
        categoryCounts: [CADCategoryCount],
        challengeInputDigest: String
    ) throws {
        guard !schema.isEmpty, !catalog.isEmpty, !tolerancePolicy.isEmpty,
              challengeInputDigest.count == 64,
              challengeInputDigest.allSatisfy({ $0.isNumber || ("a"..."f").contains($0) }) else {
            throw CADBenchmarkError.malformedManifest("Manifest version or digest is invalid.")
        }
        self.schema = schema
        self.catalog = catalog
        self.tolerancePolicy = tolerancePolicy
        self.orderedCaseIDs = orderedCaseIDs
        self.categoryCounts = categoryCounts
        self.challengeInputDigest = challengeInputDigest
        let payload = CADBenchmarkManifestDigestPayload(
            schema: schema,
            catalog: catalog,
            tolerancePolicy: tolerancePolicy,
            orderedCaseIDs: orderedCaseIDs,
            categoryCounts: categoryCounts,
            challengeInputDigest: challengeInputDigest
        )
        self.digest = try CADBenchmarkManifestDigest.compute(payload)
    }

    public func validate() throws {
        guard schema == Self.schemaVersion,
              catalog == Self.catalogVersion,
              tolerancePolicy == Self.tolerancePolicyVersion else {
            throw CADBenchmarkError.malformedManifest("Unsupported manifest version.")
        }
        guard challengeInputDigest.count == 64,
              challengeInputDigest.allSatisfy({ $0.isNumber || ("a"..."f").contains($0) }) else {
            throw CADBenchmarkError.malformedManifest("Challenge input digest is invalid.")
        }
        guard orderedCaseIDs.count == 100,
              orderedCaseIDs == orderedCaseIDs.sorted(),
              Set(orderedCaseIDs).count == 100 else {
            throw CADBenchmarkError.catalogDrift(
                expected: "100 unique lexically ordered case IDs",
                actual: "invalid manifest case IDs"
            )
        }
        for id in orderedCaseIDs {
            try id.validate()
        }
        let expectedCounts = CADBenchmarkCategory.allCases
            .sorted { $0.rawValue < $1.rawValue }
            .map { CADCategoryCount(category: $0, count: $0.expectedCount) }
        guard categoryCounts == expectedCounts else {
            throw CADBenchmarkError.catalogDrift(
                expected: "fixed category counts",
                actual: "invalid manifest category counts"
            )
        }
        let payload = CADBenchmarkManifestDigestPayload(
            schema: schema,
            catalog: catalog,
            tolerancePolicy: tolerancePolicy,
            orderedCaseIDs: orderedCaseIDs,
            categoryCounts: categoryCounts,
            challengeInputDigest: challengeInputDigest
        )
        let recomputed = try CADBenchmarkManifestDigest.compute(payload)
        guard recomputed == digest else {
            throw CADBenchmarkError.catalogDrift(expected: digest, actual: recomputed)
        }
    }
}

private struct CADBenchmarkManifestDigestPayload: Codable {
    let schema: String
    let catalog: String
    let tolerancePolicy: String
    let orderedCaseIDs: [CADBenchmarkCaseID]
    let categoryCounts: [CADCategoryCount]
    let challengeInputDigest: String
}

private enum CADBenchmarkManifestDigest {
    static func compute(_ payload: CADBenchmarkManifestDigestPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        return StableDigest.sha256Hex(for: data)
    }
}
