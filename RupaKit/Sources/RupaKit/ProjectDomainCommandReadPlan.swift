import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation

/// One immutable domain read lowered against an exact published project state.
public struct ProjectDomainCommandReadPlan: Sendable {
    public let resolution: DomainCommandPlanResolution
    public let baseProjectID: ProjectID
    public let baseGeneration: DocumentGeneration
    public let baseTransactionRevision: DocumentTransactionRevision
    public let basePublicationSequence: UInt64
    public let baseWorkspaceRevision: WorkspaceRevision
    public let preparedAutomation: PreparedAutomationBatch?

    public var route: DomainCommandRoute {
        resolution.route
    }

    init(
        resolution: DomainCommandPlanResolution,
        baseProjectID: ProjectID,
        baseGeneration: DocumentGeneration,
        baseTransactionRevision: DocumentTransactionRevision,
        basePublicationSequence: UInt64,
        baseWorkspaceRevision: WorkspaceRevision,
        preparedAutomation: PreparedAutomationBatch?
    ) {
        self.resolution = resolution
        self.baseProjectID = baseProjectID
        self.baseGeneration = baseGeneration
        self.baseTransactionRevision = baseTransactionRevision
        self.basePublicationSequence = basePublicationSequence
        self.baseWorkspaceRevision = baseWorkspaceRevision
        self.preparedAutomation = preparedAutomation
    }
}
