import RupaCoreTypes
import RupaViewportScene

public struct MeshSourcePresentationPicker: MeshSourcePresentationPicking, Sendable {
    public init() {}

    public func makeIndex(
        for scene: UniversalViewportScene,
        navigation: MeshSourcePresentationNavigationMap
    ) throws -> MeshSourcePresentationPickIndex {
        try MeshSourcePresentationPickIndex(
            scene: scene,
            navigation: navigation
        )
    }

    public func resolve(
        identity: MeshSourcePresentationPickIdentity,
        in index: MeshSourcePresentationPickIndex,
        expectedSnapshotID: EvaluationSnapshotID
    ) throws -> MeshSourcePresentationPickRecord {
        try index.record(
            for: identity,
            expectedSnapshotID: expectedSnapshotID
        )
    }
}
