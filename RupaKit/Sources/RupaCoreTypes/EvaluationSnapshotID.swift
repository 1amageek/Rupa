public struct EvaluationSnapshotID: Codable, Equatable, Hashable, Sendable {
    public let projectID: ProjectID
    public let sourceRevision: DocumentTransactionRevision

    public init(projectID: ProjectID, sourceRevision: DocumentTransactionRevision) {
        self.projectID = projectID
        self.sourceRevision = sourceRevision
    }
}
