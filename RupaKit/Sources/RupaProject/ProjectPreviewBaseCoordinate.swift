import RupaCoreTypes

/// The published authority coordinates from which one isolated preview was staged.
public struct ProjectPreviewBaseCoordinate: Equatable, Sendable {
    public let projectID: ProjectID
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let documentGeneration: DocumentGeneration

    public init(
        projectID: ProjectID,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        documentGeneration: DocumentGeneration
    ) {
        self.projectID = projectID
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
        self.documentGeneration = documentGeneration
    }
}
