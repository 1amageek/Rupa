import SwiftCAD
import RupaCoreTypes

/// One visible actual body in its immutable original scene occurrence.
public struct DrawingOccurrenceBodyPlacement: Sendable {
    public let occurrenceID: SceneOccurrenceID
    public let sceneNodeID: SceneNodeID
    public let sourceSceneNodeID: SceneNodeID
    public let featureID: FeatureID
    public let placement: ScenePlacement
    public let original: BRepDrawingPlacement
}
