import Foundation

public struct CADCapabilityStatus: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let version: String
    public let available: Bool
    public let reasonCode: String?

    public init(id: String, version: String, available: Bool, reasonCode: String? = nil) {
        self.id = id
        self.version = version
        self.available = available
        self.reasonCode = reasonCode
    }

    public func validate() throws {
        guard !id.isEmpty,
              id.trimmingCharacters(in: .whitespacesAndNewlines) == id,
              !version.isEmpty,
              version.trimmingCharacters(in: .whitespacesAndNewlines) == version else {
            throw CADBenchmarkError.malformedManifest("Capability status has an invalid identity.")
        }
        if available {
            guard reasonCode == nil else {
                throw CADBenchmarkError.malformedManifest(
                    "Available capability \(id) must not have an unavailable reason."
                )
            }
        } else {
            guard let reasonCode, !reasonCode.isEmpty else {
                throw CADBenchmarkError.malformedManifest(
                    "Unavailable capability \(id) must have a typed reason code."
                )
            }
        }
    }
}
