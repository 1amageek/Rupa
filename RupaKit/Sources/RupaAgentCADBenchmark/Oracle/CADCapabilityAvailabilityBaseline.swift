import Foundation
import RupaCoreTypes

struct CADCapabilityAvailabilityBaseline: Codable, Equatable, Sendable {
    static let schemaVersion = "t12.capability-availability.v1"

    let schemaVersion: String
    let version: String
    let statuses: [Status]
    let digest: String

    init(snapshot: CADCapabilitySnapshot) throws {
        try snapshot.validate()
        self.schemaVersion = Self.schemaVersion
        self.version = snapshot.version
        self.statuses = snapshot.statuses
            .map(Status.init)
            .sorted(by: Status.isOrderedBefore)
        self.digest = try Self.computeDigest(
            Payload(schemaVersion: schemaVersion, version: version, statuses: statuses)
        )
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
