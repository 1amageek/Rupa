import Foundation

public struct CapabilityTargetDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var summary: String

    public init(id: String, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Capability target IDs must not be empty."
            )
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Capability target names must not be empty."
            )
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Capability target summaries must not be empty."
            )
        }
    }
}
