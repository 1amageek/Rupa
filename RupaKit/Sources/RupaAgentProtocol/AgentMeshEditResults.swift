import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaKit

/// Non-publishing Mesh edit proposal. It contains no internal project view.
public struct AgentMeshEditPreviewResult: Codable, Equatable, Sendable {
    public let coordinates: AgentProjectViewCoordinates
    public let sourceID: GeometrySourceID
    public let previousContentIdentity: ContentIdentity
    public let proposedContentIdentity: ContentIdentity
    public let receipt: MeshEditReceipt
    public let didMutate: Bool
    public let proposedTransactionRevision: DocumentTransactionRevision
    public let proposedDocumentGeneration: DocumentGeneration

    public init(
        coordinates: AgentProjectViewCoordinates,
        sourceID: GeometrySourceID,
        previousContentIdentity: ContentIdentity,
        proposedContentIdentity: ContentIdentity,
        receipt: MeshEditReceipt,
        didMutate: Bool,
        proposedTransactionRevision: DocumentTransactionRevision,
        proposedDocumentGeneration: DocumentGeneration
    ) {
        self.coordinates = coordinates
        self.sourceID = sourceID
        self.previousContentIdentity = previousContentIdentity
        self.proposedContentIdentity = proposedContentIdentity
        self.receipt = receipt
        self.didMutate = didMutate
        self.proposedTransactionRevision = proposedTransactionRevision
        self.proposedDocumentGeneration = proposedDocumentGeneration
    }
}

/// Publishing Mesh edit result with the exact new source handle.
public struct AgentMeshEditCommitResult: Codable, Equatable, Sendable {
    public let coordinates: AgentProjectViewCoordinates
    public let handle: ProjectMeshSourceHandle
    public let sourceID: GeometrySourceID
    public let previousContentIdentity: ContentIdentity
    public let contentIdentity: ContentIdentity
    public let receipt: MeshEditReceipt
    public let didMutate: Bool

    public init(
        coordinates: AgentProjectViewCoordinates,
        handle: ProjectMeshSourceHandle,
        sourceID: GeometrySourceID,
        previousContentIdentity: ContentIdentity,
        contentIdentity: ContentIdentity,
        receipt: MeshEditReceipt,
        didMutate: Bool
    ) {
        self.coordinates = coordinates
        self.handle = handle
        self.sourceID = sourceID
        self.previousContentIdentity = previousContentIdentity
        self.contentIdentity = contentIdentity
        self.receipt = receipt
        self.didMutate = didMutate
    }
}
