import RupaCore
import SwiftCAD

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
    public var reference: SceneNodeReference
    public var featureID: FeatureID? { reference.featureID }
    public var sceneNodeID: SceneNodeID
    public var baseLocalTransform: Transform3D
    public var localTransform: Transform3D
    public var baseParentWorldTransform: Transform3D

    public init(
        featureID: FeatureID,
        sceneNodeID: SceneNodeID,
        baseLocalTransform: Transform3D,
        localTransform: Transform3D,
        baseParentWorldTransform: Transform3D = .identity
    ) {
        self.reference = .body(featureID)
        self.sceneNodeID = sceneNodeID
        self.baseLocalTransform = baseLocalTransform
        self.localTransform = localTransform
        self.baseParentWorldTransform = baseParentWorldTransform
    }

    public init(reference: SceneNodeReference, sceneNodeID: SceneNodeID,
                baseLocalTransform: Transform3D, localTransform: Transform3D,
                baseParentWorldTransform: Transform3D) {
        self.reference = reference
        self.sceneNodeID = sceneNodeID
        self.baseLocalTransform = baseLocalTransform
        self.localTransform = localTransform
        self.baseParentWorldTransform = baseParentWorldTransform
    }

    /// Validates all coordinates used by the gesture against the current source.
    public func validate(in document: DesignDocument) throws {
        guard let node = document.productMetadata.sceneNodes[sceneNodeID],
              reference.kind == .body || reference.kind == .authoredMesh,
              node.reference == reference, !node.isLocked,
              node.localTransform == baseLocalTransform,
              try ViewportSceneNodeParentFrames(document: document)
                .parentWorldTransform(of: sceneNodeID) == baseParentWorldTransform else {
            throw EditorError(code: .commandInvalid,
                              message: "The body placement baseline changed during the gesture.")
        }
    }
}
