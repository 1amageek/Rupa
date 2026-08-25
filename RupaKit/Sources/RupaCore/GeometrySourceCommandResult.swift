import RupaCoreTypes
import RupaGeometry

public enum GeometrySourceCommandResult: Equatable, Sendable {
    public struct AuthoredMeshEdit: Equatable, Sendable {
        public let sourceID: GeometrySourceID
        public let previousSourceIdentity: ContentIdentity
        public let sourceIdentity: ContentIdentity
        public let addedFaceID: MeshFaceID?
        public let didMutate: Bool
        public let copyTelemetry: GeometryCopyTelemetry

        public init(
            sourceID: GeometrySourceID,
            previousSourceIdentity: ContentIdentity,
            sourceIdentity: ContentIdentity,
            addedFaceID: MeshFaceID?,
            didMutate: Bool,
            copyTelemetry: GeometryCopyTelemetry
        ) {
            self.sourceID = sourceID
            self.previousSourceIdentity = previousSourceIdentity
            self.sourceIdentity = sourceIdentity
            self.addedFaceID = addedFaceID
            self.didMutate = didMutate
            self.copyTelemetry = copyTelemetry
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

    case authoredMeshEdit(AuthoredMeshEdit)
    case representationSelection(RepresentationSelection)

    public var didMutate: Bool {
        switch self {
        case .authoredMeshEdit(let result):
            result.didMutate
        case .representationSelection(let result):
            result.didMutate
        }
    }

    public var copyTelemetry: GeometryCopyTelemetry {
        switch self {
        case .authoredMeshEdit(let result):
            result.copyTelemetry
        case .representationSelection:
            GeometryCopyTelemetry()
        }
    }
}
