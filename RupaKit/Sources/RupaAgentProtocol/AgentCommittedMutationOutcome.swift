import RupaCoreTypes
import RupaCore

/// A mutation receipt returned when project authority committed but response
/// projection failed. Clients must refresh and must not retry the mutation.
public struct AgentCommittedMutationOutcome: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Equatable, Sendable {
        case viewProjection
        case domainResultProjection
    }

    public enum Mutation: String, Codable, Equatable, Sendable {
        case source
        case interaction
        case undo
        case redo
        case evaluation
    }

    public enum RetryDisposition: String, Codable, Equatable, Sendable {
        case mustNotRetry
    }

    public let stage: Stage
    public let mutation: Mutation
    public let requestMethod: String
    public let projectID: ProjectID
    public let documentGeneration: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let workspaceRevision: WorkspaceRevision
    public let retryDisposition: RetryDisposition
    public let message: String

    public init(
        stage: Stage,
        mutation: Mutation,
        requestMethod: String,
        projectID: ProjectID,
        documentGeneration: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        workspaceRevision: WorkspaceRevision,
        retryDisposition: RetryDisposition = .mustNotRetry,
        message: String
    ) {
        self.stage = stage
        self.mutation = mutation
        self.requestMethod = requestMethod
        self.projectID = projectID
        self.documentGeneration = documentGeneration
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
        self.workspaceRevision = workspaceRevision
        self.retryDisposition = retryDisposition
        self.message = message
    }
}
