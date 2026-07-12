import Foundation

public struct CapabilityAvailability: Codable, Equatable, Sendable {
    public var surfaces: Set<CapabilitySurface>
    public var disabledReason: String?

    public init(
        surfaces: Set<CapabilitySurface>,
        disabledReason: String? = nil
    ) {
        self.surfaces = surfaces
        self.disabledReason = disabledReason
    }

    public func validate() throws {
        if let disabledReason,
           disabledReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Capability availability disabled reasons must not be empty."
            )
        }
        guard disabledReason == nil || surfaces.isEmpty else {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "A capability cannot be both available and disabled."
            )
        }
        guard !surfaces.isEmpty || disabledReason != nil else {
            throw CapabilityRegistryError(
                code: .invalidDescriptor,
                message: "Unavailable capabilities must declare a disabled reason."
            )
        }
    }
}
