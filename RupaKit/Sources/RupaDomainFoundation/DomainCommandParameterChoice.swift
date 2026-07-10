import Foundation

public struct DomainCommandParameterChoice: Codable, Equatable, Sendable {
    public var value: String
    public var label: String
    public var summary: String

    public init(
        value: String,
        label: String,
        summary: String
    ) {
        self.value = value
        self.label = label
        self.summary = summary
    }

    public func validate() throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain command parameter choice values must not be empty."
            )
        }
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain command parameter choice labels must not be empty."
            )
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain command parameter choice summaries must not be empty."
            )
        }
    }
}
