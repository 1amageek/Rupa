import RupaCore
import RupaCoreTypes

public struct MeshSourcePresentationPickRecord: Equatable, Sendable {
    public let identity: MeshSourcePresentationPickIdentity
    public let snapshotID: EvaluationSnapshotID
    public let occurrenceID: SceneOccurrenceID
    public let sceneNodeID: SceneNodeID

    public init(
        identity: MeshSourcePresentationPickIdentity,
        snapshotID: EvaluationSnapshotID,
        occurrenceID: SceneOccurrenceID,
        sceneNodeID: SceneNodeID
    ) {
        self.identity = identity
        self.snapshotID = snapshotID
        self.occurrenceID = occurrenceID
        self.sceneNodeID = sceneNodeID
    }
}
