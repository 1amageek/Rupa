import Foundation
import RupaCoreTypes

struct CADCapabilityAvailabilityBaseline: Codable, Equatable, Sendable {
    static let schemaVersion = "t12.capability-availability.v1"

    let schemaVersion: String
    let version: String
    let statuses: [Status]
    let digest: String

    init(contexts: [CADCandidateContext]) throws {
        guard contexts.count == 100 else {
            throw CADBenchmarkBaselineError.invalidContextCount(
                expected: 100,
                actual: contexts.count
            )
        }
        let manifest = try CADBenchmarkCatalog().manifest
        guard contexts.map(\.challenge.id).sorted() == manifest.orderedCaseIDs else {
            throw CADBenchmarkBaselineError.invalidContextIdentity
        }
        for context in contexts {
            try context.validate()
            guard context.capabilities.status(
                for: context.challenge.requiredCapability
            ) != nil else {
                throw CADBenchmarkBaselineError.missingCapabilityStatus(
                    caseID: context.challenge.id.rawValue
                )
            }
        }
        try self.init(snapshots: contexts.map(\.capabilities))
        guard statuses.count == CADBenchmarkCategory.allCases.count else {
            throw CADBenchmarkBaselineError.invalidContextIdentity
        }
    }

    init(snapshot: CADCapabilitySnapshot) throws {
        try self.init(snapshots: [snapshot])
    }

    private init(snapshots: [CADCapabilitySnapshot]) throws {
        guard let first = snapshots.first else {
            throw CADBenchmarkBaselineError.invalidContextCount(expected: 1, actual: 0)
        }
        for snapshot in snapshots {
            try snapshot.validate()
            guard snapshot.version == first.version else {
                throw CADBenchmarkBaselineError.capabilitySnapshotVersionDrift(
                    expected: first.version,
                    actual: snapshot.version
                )
            }
        }
        var merged: [String: Status] = [:]
        for status in snapshots.flatMap(\.statuses).map(Status.init) {
            let identity = "\(status.id)@\(status.version)"
            if let existing = merged[identity], existing != status {
                throw CADBenchmarkBaselineError.capabilityStatusDrift(identity: identity)
            }
            merged[identity] = status
        }
        self.schemaVersion = Self.schemaVersion
        self.version = first.version
        self.statuses = merged.values.sorted(by: Status.isOrderedBefore)
        self.digest = try Self.computeDigest(
            Payload(schemaVersion: schemaVersion, version: version, statuses: statuses)
        )
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              !version.isEmpty,
              version.trimmingCharacters(in: .whitespacesAndNewlines) == version else {
            throw CADBenchmarkError.malformedManifest("Capability availability baseline identity is invalid.")
        }
        guard statuses == statuses.sorted(by: Status.isOrderedBefore) else {
            throw CADBenchmarkError.catalogDrift(
                expected: "lexically ordered capability availability statuses",
                actual: "unordered capability availability statuses"
            )
        }
        var identities = Set<String>()
        for status in statuses {
            let capabilityStatus = CADCapabilityStatus(
                id: status.id,
                version: status.version,
                available: status.available,
                reasonCode: status.reasonCode
            )
            try capabilityStatus.validate()
            guard identities.insert("\(status.id)@\(status.version)").inserted else {
                throw CADBenchmarkError.malformedManifest(
                    "Duplicate capability availability status \(status.id)@\(status.version)."
                )
            }
        }
        let recomputed = try Self.computeDigest(
            Payload(schemaVersion: schemaVersion, version: version, statuses: statuses)
        )
        guard recomputed == digest else {
            throw CADBenchmarkError.catalogDrift(expected: digest, actual: recomputed)
        }
    }

    struct Status: Codable, Equatable, Hashable, Sendable {
        let id: String
        let version: String
        let available: Bool
        let reasonCode: String?

        init(_ status: CADCapabilityStatus) {
            id = status.id
            version = status.version
            available = status.available
            reasonCode = status.reasonCode
        }

        static func isOrderedBefore(_ lhs: Status, _ rhs: Status) -> Bool {
            (lhs.id, lhs.version, lhs.available ? 1 : 0, lhs.reasonCode ?? "")
                < (rhs.id, rhs.version, rhs.available ? 1 : 0, rhs.reasonCode ?? "")
        }
    }

    private struct Payload: Codable {
        let schemaVersion: String
        let version: String
        let statuses: [Status]
    }

    private static func computeDigest(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return StableDigest.sha256Hex(for: try encoder.encode(payload))
    }
}
