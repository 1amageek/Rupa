import RupaCore
import RupaViewportScene

/// What a body transform press captures so its release can commit the body's
/// placement, prepared once per frame by the overlay producer and read back
/// unchanged by the input owner for the whole gesture.
///
/// Every addressable occurrence retains its own local and parent-world frames,
/// including members of a group that share a feature. Release measures a world
/// mutation from the mounted frame and composes it through these baselines.
/// The workspace rejects a commit when either baseline has changed.
struct ViewportBodyPlacementBaseline: Equatable, Sendable {
    let featureID: FeatureID
    let sceneNodeID: SceneNodeID
    let baseLocalTransform: Transform3D
    let parentWorldTransform: Transform3D

    init(
        featureID: FeatureID,
        sceneNodeID: SceneNodeID,
        baseLocalTransform: Transform3D,
        parentWorldTransform: Transform3D
    ) {
        self.featureID = featureID
        self.sceneNodeID = sceneNodeID
        self.baseLocalTransform = baseLocalTransform
        self.parentWorldTransform = parentWorldTransform
    }
}
