import RupaCoreTypes
import RupaViewportScene

public protocol MeshSourcePresentationPicking: Sendable {
    func makeIndex(
        for scene: UniversalViewportScene,
        navigation: MeshSourcePresentationNavigationMap
    ) throws -> MeshSourcePresentationPickIndex

    func resolve(
        identity: MeshSourcePresentationPickIdentity,
        in index: MeshSourcePresentationPickIndex,
        expectedSnapshotID: EvaluationSnapshotID
    ) throws -> MeshSourcePresentationPickRecord
}
