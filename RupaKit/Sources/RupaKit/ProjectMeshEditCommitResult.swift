import RupaCoreTypes
import RupaGeometry

public struct ProjectMeshEditCommitResult: Sendable {
    public let view: ProjectViewSnapshot
    public let handle: ProjectMeshSourceHandle
    public let sourceID: GeometrySourceID
    public let previousContentIdentity: ContentIdentity
    public let contentIdentity: ContentIdentity
    public let receipt: MeshEditReceipt
    public let didMutate: Bool

    public var copyTelemetry: GeometryCopyTelemetry {
        receipt.telemetry
    }

    public init(
        view: ProjectViewSnapshot,
        handle: ProjectMeshSourceHandle,
        sourceID: GeometrySourceID,
        previousContentIdentity: ContentIdentity,
        contentIdentity: ContentIdentity,
        receipt: MeshEditReceipt,
        didMutate: Bool
    ) {
        self.view = view
        self.handle = handle
        self.sourceID = sourceID
        self.previousContentIdentity = previousContentIdentity
        self.contentIdentity = contentIdentity
        self.receipt = receipt
        self.didMutate = didMutate
    }
}
