import SwiftCAD
import RupaCoreTypes

/// Source-only occurrence; authored factor order is independent of display matrices.
public struct OriginalDrawingSceneOccurrence: Sendable {
    public let id: SceneOccurrenceID
    public let sourceSceneNodeID: SceneNodeID
    public let sceneNodeID: SceneNodeID
    public let originalTransformFactors: [Transform3D]
    public let isVisible: Bool
}
