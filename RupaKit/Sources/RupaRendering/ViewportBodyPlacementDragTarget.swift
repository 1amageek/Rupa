import RupaCore

/// One committed body placement: the scene node whose local frame changes, the
/// frame that node held when the gesture began, and the frame the gesture
/// produced.
///
/// A body translate moves where the body is placed rather than what the body
/// is made of, which is why it names a scene node and a frame instead of a
/// profile edit. The baseline travels with the commit because the workspace,
/// not the viewport, owns the document. The workspace refuses the command when
/// the stored local transform no longer equals `baseLocalTransform`, rather
/// than overwriting a frame another edit changed while the drag was open.
public struct ViewportBodyPlacementDragTarget: Equatable, Sendable {
    public var featureID: FeatureID
    public var sceneNodeID: SceneNodeID
    public var baseLocalTransform: Transform3D
    public var localTransform: Transform3D

    public init(
        featureID: FeatureID,
        sceneNodeID: SceneNodeID,
        baseLocalTransform: Transform3D,
        localTransform: Transform3D
    ) {
        self.featureID = featureID
        self.sceneNodeID = sceneNodeID
        self.baseLocalTransform = baseLocalTransform
        self.localTransform = localTransform
    }
}
