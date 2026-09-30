import Foundation

/// Names one evaluated content of a project.
///
/// A published evaluation is named by the transaction revision it evaluated. An unpublished
/// candidate (a source preview) proposes the next revision, and every candidate staged from the
/// same base proposes the same one, so a candidate also carries a token of its own: two IDs are
/// equal only when they name the same evaluated content. A candidate never becomes a published
/// evaluation; committing re-evaluates under the committed revision.
public struct EvaluationSnapshotID: Codable, Equatable, Hashable, Sendable {
    public let projectID: ProjectID
    public let purpose: GeometryRepresentationPurpose
    public let sourceRevision: DocumentTransactionRevision
    /// Nil for a published evaluation; the candidate's own token otherwise.
    public let candidate: UUID?

    public init(
        projectID: ProjectID,
        purpose: GeometryRepresentationPurpose,
        sourceRevision: DocumentTransactionRevision,
        candidate: UUID? = nil
    ) {
        self.projectID = projectID
        self.purpose = purpose
        self.sourceRevision = sourceRevision
        self.candidate = candidate
    }
}
