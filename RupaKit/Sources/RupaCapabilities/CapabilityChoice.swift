import Foundation

public struct CapabilityChoice: Codable, Equatable, Sendable {
    public var value: String
    public var label: String
    public var summary: String

    public init(value: String, label: String, summary: String) {
        self.value = value
        self.label = label
        self.summary = summary
    }

    public func validate() throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Capability choice values must not be empty."
            )
        }
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Capability choice labels must not be empty."
            )
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Capability choice summaries must not be empty."
            )
        }
    }
}
