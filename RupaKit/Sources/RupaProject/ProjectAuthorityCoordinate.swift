import RupaCoreTypes

/// The exact source-authority coordinate required to begin a project operation.
public struct ProjectAuthorityCoordinate: Equatable, Sendable {
    public let projectID: ProjectID
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64

    public init(
        projectID: ProjectID,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64
    ) {
        self.projectID = projectID
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
    }
}
