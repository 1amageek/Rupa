import RupaCoreTypes
import RupaGeometry
import RupaKit
import RupaProjectModel

/// Publishing CAD Make Editable result projected without encoding ProjectViewSnapshot.
public struct AgentMakeEditableResult: Codable, Equatable, Sendable {
    public let coordinates: AgentProjectViewCoordinates
    public let handle: ProjectMeshSourceHandle
    public let sceneNodeID: SceneNodeID
    public let sourceRepresentationID: GeometryRepresentationID
    public let authoredMeshSourceID: GeometrySourceID
    public let authoredMeshRepresentationID: GeometryRepresentationID
    public let evaluationSnapshotID: EvaluationSnapshotID
    public let cadSourceIdentity: ContentIdentity
    public let authoredMeshContentIdentity: ContentIdentity
    public let provenance: AuthoredMeshProvenance
    public let switchedPresentationSelection: Bool
    public let copyTelemetry: GeometryCopyTelemetry

    public init(
        coordinates: AgentProjectViewCoordinates,
        handle: ProjectMeshSourceHandle,
        sceneNodeID: SceneNodeID,
        sourceRepresentationID: GeometryRepresentationID,
        authoredMeshSourceID: GeometrySourceID,
        authoredMeshRepresentationID: GeometryRepresentationID,
        evaluationSnapshotID: EvaluationSnapshotID,
        cadSourceIdentity: ContentIdentity,
        authoredMeshContentIdentity: ContentIdentity,
        provenance: AuthoredMeshProvenance,
        switchedPresentationSelection: Bool,
        copyTelemetry: GeometryCopyTelemetry
    ) {
        self.coordinates = coordinates
        self.handle = handle
        self.sceneNodeID = sceneNodeID
        self.sourceRepresentationID = sourceRepresentationID
        self.authoredMeshSourceID = authoredMeshSourceID
        self.authoredMeshRepresentationID = authoredMeshRepresentationID
        self.evaluationSnapshotID = evaluationSnapshotID
        self.cadSourceIdentity = cadSourceIdentity
        self.authoredMeshContentIdentity = authoredMeshContentIdentity
        self.provenance = provenance
        self.switchedPresentationSelection = switchedPresentationSelection
        self.copyTelemetry = copyTelemetry
    }
}
