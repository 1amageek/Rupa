import RupaCore
import RupaViewportScene

/// What a body transform press captures so its release can commit the body's
/// placement, prepared once per frame by the overlay producer and read back
/// unchanged by the input owner for the whole gesture.
///
/// The gizmo's ghost preview is a world translation of the body's own world
/// box, so the release already knows the world delta and asks the mounted
/// frame for nothing. Turning that delta into the scene node's new local frame
/// needs the frame the node held at press and the world frame of its parent,
/// both resolved by the producer pass that drew the handle. Capturing them at
/// press is what lets the workspace tell a commit onto the frame the gesture
/// measured from a commit onto a frame another edit changed meanwhile.
///
/// The producer prepares this only for a single-body gizmo whose scene item
/// names a scene node. A group gizmo has no single node to address and a body
/// item carrying no node names no commit target, so both stay previews and
/// carry no baseline.
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
