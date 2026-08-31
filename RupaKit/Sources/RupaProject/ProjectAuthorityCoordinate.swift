import RupaCore
import RupaCoreTypes

/// The exact source-authority coordinate required to begin a project operation.
public struct ProjectAuthorityCoordinate: Equatable, Sendable {
    public let projectID: ProjectID
    public let documentGeneration: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let workspaceRevision: WorkspaceRevision

    public init(
        projectID: ProjectID,
        documentGeneration: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        workspaceRevision: WorkspaceRevision
    ) {
        self.projectID = projectID
        self.documentGeneration = documentGeneration
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
        self.workspaceRevision = workspaceRevision
    }
}
