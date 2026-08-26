import RupaCore
import RupaCoreTypes
import RupaDomainFoundation

/// One domain mutation lowered to a typed project workspace action.
public struct ProjectDomainCommandActionPlan: Sendable {
    public let action: ProjectWorkspaceAction
    public let resolution: DomainCommandPlanResolution
    public let baseProjectID: ProjectID
    public let baseGeneration: DocumentGeneration
    public let baseTransactionRevision: DocumentTransactionRevision
    public let basePublicationSequence: UInt64
    public let baseWorkspaceRevision: WorkspaceRevision

    public var capabilityID: DomainCapabilityID {
        resolution.request.capabilityID
    }

    public var namespace: SemanticNamespaceID {
        resolution.request.namespace
    }

    public var route: DomainCommandRoute {
        resolution.route
    }

    public var dryRun: Bool {
        resolution.request.dryRun
    }

    init(
        action: ProjectWorkspaceAction,
        resolution: DomainCommandPlanResolution,
        baseProjectID: ProjectID,
        baseGeneration: DocumentGeneration,
        baseTransactionRevision: DocumentTransactionRevision,
        basePublicationSequence: UInt64,
        baseWorkspaceRevision: WorkspaceRevision
    ) {
        self.action = action
        self.resolution = resolution
        self.baseProjectID = baseProjectID
        self.baseGeneration = baseGeneration
        self.baseTransactionRevision = baseTransactionRevision
        self.basePublicationSequence = basePublicationSequence
        self.baseWorkspaceRevision = baseWorkspaceRevision
    }
}
