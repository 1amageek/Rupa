import RupaDomainFoundation

struct WorkspaceCommandDescriptor: Identifiable, Equatable, Sendable {
    enum Category: String, Equatable, Sendable {
        case domain
    }

    var id: String
    var category: Category
    var title: String
    var subtitle: String
    var systemImage: String
    var mutatesDocument: Bool
    var supportsDryRun: Bool
    var targetSummary: String
    var failureMode: String
    var domainCapability: DomainCapabilityDescriptor

    init(domainCapability descriptor: DomainCapabilityDescriptor) {
        self.id = descriptor.id.rawValue
        self.category = .domain
        self.title = descriptor.name
        self.subtitle = descriptor.namespace.rawValue
        self.systemImage = descriptor.mutatesDocument ? "puzzlepiece.extension" : "checklist"
        self.mutatesDocument = descriptor.mutatesDocument
        self.supportsDryRun = descriptor.supportsDryRun
        self.targetSummary = descriptor.targetKinds.isEmpty
            ? "Any"
            : descriptor.targetKinds.map(\.rawValue).joined(separator: ", ")
        self.failureMode = descriptor.failureMode
        self.domainCapability = descriptor
    }
}
