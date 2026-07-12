import RupaCapabilities

public extension DomainRegistry {
    func capabilityRegistry() throws -> CapabilityRegistry {
        try CapabilityRegistry(
            descriptors: sortedCapabilityDescriptors().map {
                try $0.capabilityDescriptor()
            }
        )
    }
}
