import Foundation

public struct CapabilityResultDescriptor: Codable, Equatable, Sendable {
    public var kind: CapabilityResultKind
    public var maximumFidelity: String?

    public init(kind: CapabilityResultKind, maximumFidelity: String? = nil) {
        self.kind = kind
        self.maximumFidelity = maximumFidelity
    }

    public func validate() throws {
        if let maximumFidelity,
           maximumFidelity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Capability result fidelity must not be empty when present."
            )
        }
        if kind == .validationReport, maximumFidelity == nil {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Validation-report capabilities must declare maximum fidelity."
            )
        }
    }
}
