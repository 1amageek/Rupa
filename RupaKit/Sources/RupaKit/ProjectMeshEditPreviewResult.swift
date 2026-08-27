import RupaCoreTypes
import RupaGeometry

public struct ProjectMeshEditPreviewResult: Sendable {
    public let baseSnapshot: ProjectViewSnapshot
    public let sourceID: GeometrySourceID
    public let previousContentIdentity: ContentIdentity
    public let proposedContentIdentity: ContentIdentity
    public let receipt: MeshEditReceipt
    public let didMutate: Bool
    public let proposedTransactionRevision: DocumentTransactionRevision
    public let proposedDocumentGeneration: DocumentGeneration
    public let diagnostics: [EditorDiagnostic]

    public var copyTelemetry: GeometryCopyTelemetry {
        receipt.telemetry
    }

    public init(
        baseSnapshot: ProjectViewSnapshot,
        sourceID: GeometrySourceID,
        previousContentIdentity: ContentIdentity,
        proposedContentIdentity: ContentIdentity,
        receipt: MeshEditReceipt,
        didMutate: Bool,
        proposedTransactionRevision: DocumentTransactionRevision,
        proposedDocumentGeneration: DocumentGeneration,
        diagnostics: [EditorDiagnostic]
    ) {
        self.baseSnapshot = baseSnapshot
        self.sourceID = sourceID
        self.previousContentIdentity = previousContentIdentity
        self.proposedContentIdentity = proposedContentIdentity
        self.receipt = receipt
        self.didMutate = didMutate
        self.proposedTransactionRevision = proposedTransactionRevision
        self.proposedDocumentGeneration = proposedDocumentGeneration
        self.diagnostics = diagnostics
    }
}
