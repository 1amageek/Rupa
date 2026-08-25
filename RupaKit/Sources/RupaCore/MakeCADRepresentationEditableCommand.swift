import RupaCoreTypes
import RupaGeometry
import RupaProjectModel

/// Captures one modeling-purpose CAD evaluation as an explicit authored-Mesh
/// source mutation. The snapshot revision and CAD content identity make stale
/// evaluation output rejectable before it can become source authority.
public struct MakeCADRepresentationEditableCommand: Codable, Equatable, Sendable {
    public let sceneNodeID: SceneNodeID
    public let sourceRepresentationID: GeometryRepresentationID
    public let sourceReference: GeometrySourceReference
    public let evaluationSnapshotID: EvaluationSnapshotID
    public let sourceIdentity: ContentIdentity
    public let evaluatedMesh: MeshSource
    public let evaluationCopyTelemetry: GeometryCopyTelemetry
    public let authoredMeshSourceID: GeometrySourceID
    public let authoredMeshRepresentationID: GeometryRepresentationID
    public let switchesPresentationSelection: Bool

    public init(
        sceneNodeID: SceneNodeID,
        sourceRepresentationID: GeometryRepresentationID,
        sourceReference: GeometrySourceReference,
        evaluationSnapshotID: EvaluationSnapshotID,
        sourceIdentity: ContentIdentity,
        evaluatedMesh: MeshSource,
        evaluationCopyTelemetry: GeometryCopyTelemetry,
        authoredMeshSourceID: GeometrySourceID,
        authoredMeshRepresentationID: GeometryRepresentationID,
        switchesPresentationSelection: Bool
    ) throws {
        self.sceneNodeID = sceneNodeID
        self.sourceRepresentationID = sourceRepresentationID
        self.sourceReference = sourceReference
        self.evaluationSnapshotID = evaluationSnapshotID
        self.sourceIdentity = sourceIdentity
        self.evaluatedMesh = evaluatedMesh
        self.evaluationCopyTelemetry = evaluationCopyTelemetry
        self.authoredMeshSourceID = authoredMeshSourceID
        self.authoredMeshRepresentationID = authoredMeshRepresentationID
        self.switchesPresentationSelection = switchesPresentationSelection
        try validate()
    }

    public func validate() throws {
        try sourceRepresentationID.validate()
        try authoredMeshSourceID.validate()
        try authoredMeshRepresentationID.validate()
        try evaluationSnapshotID.projectID.validate()
        do {
            try sourceReference.validate()
            try evaluatedMesh.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable requires valid CAD reference and evaluated Mesh payloads: \(error)."
            )
        }
        guard case .cad = sourceReference else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable accepts only a CAD source representation."
            )
        }
        guard evaluationSnapshotID.purpose == .modeling else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable requires a modeling-purpose evaluation snapshot."
            )
        }
        guard sourceIdentity.domain == AuthoredMeshProvenance.cadSourceIdentityDomain else {
            throw EditorError(
                code: .commandInvalid,
                message: "Make Editable requires a CAD source content identity."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sceneNodeID
        case sourceRepresentationID
        case sourceReference
        case evaluationSnapshotID
        case sourceIdentity
        case evaluatedMesh
        case evaluationCopyTelemetry
        case authoredMeshSourceID
        case authoredMeshRepresentationID
        case switchesPresentationSelection
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sceneNodeID: container.decode(SceneNodeID.self, forKey: .sceneNodeID),
            sourceRepresentationID: container.decode(
                GeometryRepresentationID.self,
                forKey: .sourceRepresentationID
            ),
            sourceReference: container.decode(
                GeometrySourceReference.self,
                forKey: .sourceReference
            ),
            evaluationSnapshotID: container.decode(
                EvaluationSnapshotID.self,
                forKey: .evaluationSnapshotID
            ),
            sourceIdentity: container.decode(ContentIdentity.self, forKey: .sourceIdentity),
            evaluatedMesh: container.decode(MeshSource.self, forKey: .evaluatedMesh),
            evaluationCopyTelemetry: container.decode(
                GeometryCopyTelemetry.self,
                forKey: .evaluationCopyTelemetry
            ),
            authoredMeshSourceID: container.decode(
                GeometrySourceID.self,
                forKey: .authoredMeshSourceID
            ),
            authoredMeshRepresentationID: container.decode(
                GeometryRepresentationID.self,
                forKey: .authoredMeshRepresentationID
            ),
            switchesPresentationSelection: container.decode(
                Bool.self,
                forKey: .switchesPresentationSelection
            )
        )
    }
}
