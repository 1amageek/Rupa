import Foundation

public struct CADCapabilitySnapshot: Codable, Equatable, Sendable {
    public let version: String
    public let statuses: [CADCapabilityStatus]

    public init(version: String, statuses: [CADCapabilityStatus]) {
        self.version = version
        self.statuses = statuses
    }

    public func status(for capability: CADCapabilityRequirement) -> CADCapabilityStatus? {
        statuses.first { $0.id == capability.id && $0.version == capability.version }
    }

    public func validate() throws {
        guard !version.isEmpty, version.trimmingCharacters(in: .whitespacesAndNewlines) == version else {
            throw CADBenchmarkError.malformedManifest("Capability snapshot version is invalid.")
        }
        var seen = Set<String>()
        for status in statuses {
            try status.validate()
            let key = "\(status.id)@\(status.version)"
            guard seen.insert(key).inserted else {
                throw CADBenchmarkError.malformedManifest("Duplicate capability status \(key).")
            }
        }
    }
}
