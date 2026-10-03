import RupaCore
import SwiftCAD

/// A command waiting for the user to pick a point in the viewport.
///
/// While a request is pending the viewport resolves clicks to points (snap, surface, construction
/// plane) instead of selecting, and Escape withdraws the request.
enum WorkspacePointPickRequest: Equatable, Sendable {
    /// The center a new radial array of the objects turns around.
    case radialArrayCenter(rootSceneNodeIDs: [SceneNodeID])
    /// The reference point Copy with Placement stores with the copied objects.
    case copyReferencePoint(rootSceneNodeIDs: [SceneNodeID])
    /// Isoparam with nothing selected: the click on a face places the line through the point
    /// clicked, along `direction`, which Tab switches.
    case isoparam(direction: SurfaceParameterDirection)

    var prompt: String {
        switch self {
        case .radialArrayCenter:
            "Click the center of the Radial Array. Esc cancels."
        case .copyReferencePoint:
            "Copy with Placement: click the reference point on the objects. Esc cancels."
        case .isoparam(let direction):
            "Isoparam: click a face where the \(direction == .u ? "U" : "V") line runs; Tab switches U and V, Esc cancels."
        }
    }
}
