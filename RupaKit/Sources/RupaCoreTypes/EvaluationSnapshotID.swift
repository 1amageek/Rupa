public struct EvaluationSnapshotID: Codable, Equatable, Hashable, Sendable {
    public let projectID: ProjectID
    public let purpose: GeometryRepresentationPurpose
    public let sourceRevision: DocumentTransactionRevision

    public init(
        projectID: ProjectID,
        purpose: GeometryRepresentationPurpose,
        sourceRevision: DocumentTransactionRevision
    ) {
        self.projectID = projectID
        self.purpose = purpose
        self.sourceRevision = sourceRevision
    }
}
