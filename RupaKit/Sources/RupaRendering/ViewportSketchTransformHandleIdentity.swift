import RupaCore
import RupaViewportScene

/// Stable identity of one sketch transform handle within one prepared frame.
///
/// A sketch transform never names `ViewportAffordanceTarget`. The affordance
/// press route resolves a body edit baseline and draws a world-bounds ghost
/// for it, so a sketch borrowing that identity would be previewed as a solid
/// box it is not. This family is the sketch's own, and the scene node it names
/// is the commit target the workspace addresses; both families now commit that
/// scene node's local frame through `ViewportWorldTransformAlgebra`.
struct ViewportSketchTransformHandleIdentity: Equatable, Sendable {
    /// Corners of the sketch's model-bounds rectangle. The rectangle's second
    /// axis is the sketch plane's local z, so `minY` names the corner at the
    /// smaller local z.
    enum Corner: CaseIterable, Equatable, Sendable {
        case minXMinY
        case maxXMinY
        case maxXMaxY
        case minXMaxY
    }

    enum Role: Equatable, Sendable {
        case translate(ViewportCoordinateAxis)
        case rotate(ViewportCoordinateAxis)
        case scale(Corner)
    }

    var featureID: FeatureID
    var sceneNodeID: SceneNodeID
    var role: Role

    init(featureID: FeatureID, sceneNodeID: SceneNodeID, role: Role) {
        self.featureID = featureID
        self.sceneNodeID = sceneNodeID
        self.role = role
    }
}
