import RupaCoreTypes
import RupaGeometry

/// An observation of a published presentation, never a source-edit authority.
public struct ViewportMeshElementHit: Equatable, Sendable {
    public let snapshotID: EvaluationSnapshotID
    public let occurrenceID: SceneOccurrenceID
    public let sourceID: GeometrySourceID
    public let element: MeshSelectionElement
}
