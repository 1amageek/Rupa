import Foundation
import RupaCoreTypes

public struct CapabilityRegistry: Sendable {
    private let descriptors: [CapabilityID: CapabilityDescriptor]

    public init(descriptors: [CapabilityDescriptor] = []) throws {
        var indexed: [CapabilityID: CapabilityDescriptor] = [:]
        for descriptor in descriptors {
            try descriptor.validate()
            guard indexed[descriptor.id] == nil else {
                throw CapabilityRegistryError(
                    code: .duplicateCapability,
                    message: "Capability \(descriptor.id.rawValue) is registered more than once."
                )
            }
            indexed[descriptor.id] = descriptor
        }
        self.descriptors = indexed
    }

    public static func merged(_ registries: [CapabilityRegistry]) throws -> CapabilityRegistry {
        try CapabilityRegistry(
            descriptors: registries.flatMap { $0.sortedDescriptors() }
        )
    }

    public var count: Int {
        descriptors.count
    }

    public func descriptor(for id: CapabilityID) -> CapabilityDescriptor? {
        descriptors[id]
    }

    public func descriptor(
        for id: CapabilityID,
        version: CapabilityVersion
    ) throws -> CapabilityDescriptor {
        guard let descriptor = descriptors[id] else {
            throw CapabilityRegistryError(
                code: .missingCapability,
                message: "No capability is registered for \(id.rawValue)."
            )
        }
        guard descriptor.version == version else {
            throw CapabilityRegistryError(
                code: .versionMismatch,
                message: "Capability \(id.rawValue) does not provide version \(version.major).\(version.minor).\(version.patch)."
            )
        }
        return descriptor
    }

    public func sortedDescriptors() -> [CapabilityDescriptor] {
        descriptors.values.sorted { lhs, rhs in
            lhs.id.rawValue < rhs.id.rawValue
        }
    }

    public func descriptors(for surface: CapabilitySurface) -> [CapabilityDescriptor] {
        sortedDescriptors().filter { descriptor in
            descriptor.availability.surfaces.contains(surface)
        }
    }
}
