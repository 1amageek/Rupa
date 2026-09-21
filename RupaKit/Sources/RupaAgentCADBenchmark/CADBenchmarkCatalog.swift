import Foundation
import RupaCoreTypes

public struct CADBenchmarkCatalog: Sendable {
    public let challenges: [CADChallenge]
    public let manifest: CADBenchmarkManifest

    /// Builds and validates the immutable T12 exactly-100 challenge catalog.
    public init() throws {
        let candidateChallenges = try CADInternalCatalogStore.entries()
            .map(\.challenge)
            .sorted { $0.id < $1.id }
        try Self.validate(challenges: candidateChallenges)

        let challengeDigest = try Self.challengeInputDigest(for: candidateChallenges)
        let counts = Self.categoryCounts(for: candidateChallenges)
        let manifest = try CADBenchmarkManifest(
            orderedCaseIDs: candidateChallenges.map(\.id),
            categoryCounts: counts,
            challengeInputDigest: challengeDigest
        )
        try manifest.validate()
        self.challenges = candidateChallenges.sorted { $0.id < $1.id }
        self.manifest = manifest
    }

    public static func make() throws -> CADBenchmarkCatalog {
        try CADBenchmarkCatalog()
    }

    public var caseIDs: [CADBenchmarkCaseID] {
        challenges.map(\.id)
    }

    public func challenge(for id: CADBenchmarkCaseID) throws -> CADChallenge {
        guard let challenge = challenges.first(where: { $0.id == id }) else {
            throw CADBenchmarkError.missingCaseID(id.rawValue)
        }
        return challenge
    }

    public func validate() throws {
        try Self.validate(challenges: challenges)
        try manifest.validate()
        guard manifest.orderedCaseIDs == caseIDs else {
            throw CADBenchmarkError.catalogDrift(
                expected: "manifest IDs matching catalog IDs",
                actual: "manifest IDs differ from catalog IDs"
            )
        }
        guard manifest.categoryCounts == Self.categoryCounts(for: challenges) else {
            throw CADBenchmarkError.catalogDrift(
                expected: "manifest counts matching catalog counts",
                actual: "manifest counts differ from catalog counts"
            )
        }
        let digest = try Self.challengeInputDigest(for: challenges)
        guard manifest.challengeInputDigest == digest else {
            throw CADBenchmarkError.catalogDrift(
                expected: manifest.challengeInputDigest,
                actual: digest
            )
        }
    }

    private static func validate(challenges: [CADChallenge]) throws {
        guard challenges.count == 100 else {
            throw CADBenchmarkError.invalidCategoryCount(category: "TOTAL", expected: 100, actual: challenges.count)
        }
        var IDs = Set<CADBenchmarkCaseID>()
        for challenge in challenges {
            try challenge.validate()
            guard IDs.insert(challenge.id).inserted else {
                throw CADBenchmarkError.duplicateCaseID(challenge.id.rawValue)
            }
        }
        let sortedIDs = challenges.map(\.id).sorted()
        guard challenges.map(\.id) == sortedIDs else {
            throw CADBenchmarkError.catalogDrift(
                expected: "lexically ordered IDs",
                actual: "unordered IDs"
            )
        }
        for category in CADBenchmarkCategory.allCases {
            let actual = challenges.filter { $0.category == category }.count
            guard actual == category.expectedCount else {
                throw CADBenchmarkError.invalidCategoryCount(
                    category: category.rawValue,
                    expected: category.expectedCount,
                    actual: actual
                )
            }
        }
    }

    private static func categoryCounts(for challenges: [CADChallenge]) -> [CADCategoryCount] {
        CADBenchmarkCategory.allCases
            .sorted { $0.rawValue < $1.rawValue }
            .map { category in
                CADCategoryCount(
                    category: category,
                    count: challenges.filter { $0.category == category }.count
                )
            }
    }

    private static func challengeInputDigest(for challenges: [CADChallenge]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(challenges)
        return StableDigest.sha256Hex(for: data)
    }

}
