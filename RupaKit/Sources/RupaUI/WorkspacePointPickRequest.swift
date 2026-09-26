import RupaCore

/// A command waiting for the user to pick a point in the viewport.
///
/// While a request is pending the viewport resolves clicks to points (snap, surface, construction
/// plane) instead of selecting, and Escape withdraws the request.
enum WorkspacePointPickRequest: Equatable, Sendable {
    /// The center a new radial array of the objects turns around.
    case radialArrayCenter(rootSceneNodeIDs: [SceneNodeID])
    /// The reference point Copy with Placement stores with the copied objects.
    case copyReferencePoint(rootSceneNodeIDs: [SceneNodeID])

    var prompt: String {
        switch self {
        case .radialArrayCenter:
            "Click the center of the Radial Array. Esc cancels."
        case .copyReferencePoint:
            "Copy with Placement: click the reference point on the objects. Esc cancels."
        }
    }
}
