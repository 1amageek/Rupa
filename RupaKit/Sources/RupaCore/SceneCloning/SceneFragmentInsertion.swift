import SwiftCAD

/// The identities one inserted copy of a ``SceneFragment`` received.
struct SceneFragmentInsertion: Sendable {
    /// The copied roots, in the fragment's root order.
    var rootSceneNodeIDs: [SceneNodeID]
    /// Every copied node, roots and carried presenters included.
    var sceneNodeIDs: [SceneNodeID]
    /// The copied features, in insertion (graph) order.
    var featureIDs: [FeatureID]
}
