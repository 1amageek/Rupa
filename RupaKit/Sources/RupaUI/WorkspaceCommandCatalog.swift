import RupaDomainFoundation

struct WorkspaceCommandCatalog: Equatable, Sendable {
    var domainCommands: [WorkspaceCommandDescriptor]

    init(domainRegistry: DomainRegistry = DomainRegistry()) {
        self.domainCommands = domainRegistry
            .sortedCapabilityDescriptors()
            .map(WorkspaceCommandDescriptor.init(domainCapability:))
    }

    var hasDomainCommands: Bool {
        !domainCommands.isEmpty
    }
}
