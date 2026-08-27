import RupaCoreTypes
import RupaGeometry

public enum GeometrySourceCommandResult: Equatable, Sendable {
    public struct AuthoredMeshEdit: Equatable, Sendable {
        public let sourceID: GeometrySourceID
        public let previousSourceIdentity: ContentIdentity
        public let sourceIdentity: ContentIdentity
        public let receipt: MeshEditReceipt
        public let didMutate: Bool

        public var copyTelemetry: GeometryCopyTelemetry {
            receipt.telemetry
        }

        public init(
            sourceID: GeometrySourceID,
            previousSourceIdentity: ContentIdentity,
            sourceIdentity: ContentIdentity,
            receipt: MeshEditReceipt,
            didMutate: Bool
        ) {
            self.sourceID = sourceID
            self.previousSourceIdentity = previousSourceIdentity
            self.sourceIdentity = sourceIdentity
            self.receipt = receipt
            self.didMutate = didMutate
        }
    }

    public struct RepresentationSelection: Equatable, Sendable {
        public let sceneNodeID: SceneNodeID
        public let purpose: GeometryRepresentationPurpose
        public let previousRepresentationID: GeometryRepresentationID
        public let representationID: GeometryRepresentationID
        public let didMutate: Bool

        public init(
            sceneNodeID: SceneNodeID,
            purpose: GeometryRepresentationPurpose,
            previousRepresentationID: GeometryRepresentationID,
            representationID: GeometryRepresentationID,
            didMutate: Bool
        ) {
            self.sceneNodeID = sceneNodeID
            self.purpose = purpose
            self.previousRepresentationID = previousRepresentationID
            self.representationID = representationID
            self.didMutate = didMutate
        }
    }

    public struct MakeEditable: Equatable, Sendable {
        public let sceneNodeID: SceneNodeID
        public let sourceRepresentationID: GeometryRepresentationID
        public let authoredMeshSourceID: GeometrySourceID
        public let authoredMeshRepresentationID: GeometryRepresentationID
        public let evaluationSnapshotID: EvaluationSnapshotID
        public let cadSourceIdentity: ContentIdentity
        public let authoredMeshContentIdentity: ContentIdentity
        public let switchedPresentationSelection: Bool
        public let copyTelemetry: GeometryCopyTelemetry

        public init(
            sceneNodeID: SceneNodeID,
            sourceRepresentationID: GeometryRepresentationID,
            authoredMeshSourceID: GeometrySourceID,
            authoredMeshRepresentationID: GeometryRepresentationID,
            evaluationSnapshotID: EvaluationSnapshotID,
            cadSourceIdentity: ContentIdentity,
            authoredMeshContentIdentity: ContentIdentity,
            switchedPresentationSelection: Bool,
            copyTelemetry: GeometryCopyTelemetry
        ) {
            self.sceneNodeID = sceneNodeID
            self.sourceRepresentationID = sourceRepresentationID
            self.authoredMeshSourceID = authoredMeshSourceID
            self.authoredMeshRepresentationID = authoredMeshRepresentationID
            self.evaluationSnapshotID = evaluationSnapshotID
            self.cadSourceIdentity = cadSourceIdentity
            self.authoredMeshContentIdentity = authoredMeshContentIdentity
            self.switchedPresentationSelection = switchedPresentationSelection
            self.copyTelemetry = copyTelemetry
        }
    }

    case authoredMeshEdit(AuthoredMeshEdit)
    case makeEditable(MakeEditable)
    case representationSelection(RepresentationSelection)

    public var didMutate: Bool {
        switch self {
        case .authoredMeshEdit(let result):
            result.didMutate
        case .makeEditable:
            true
        case .representationSelection(let result):
            result.didMutate
        }
    }

    public var copyTelemetry: GeometryCopyTelemetry {
        switch self {
        case .authoredMeshEdit(let result):
            result.copyTelemetry
        case .makeEditable(let result):
            result.copyTelemetry
        case .representationSelection:
            GeometryCopyTelemetry()
        }
    }
}
