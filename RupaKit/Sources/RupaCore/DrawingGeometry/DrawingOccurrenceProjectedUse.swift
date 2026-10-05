import SwiftCAD
import RupaCoreTypes

/// One original topological use in one actual placed occurrence.
public struct DrawingOccurrenceProjectedUse: Sendable {
    public let occurrenceID: SceneOccurrenceID
    public let sceneNodeID: SceneNodeID
    public let sourceSceneNodeID: SceneNodeID
    public let featureID: FeatureID
    public let placement: ScenePlacement
    public let original: BRepDrawingProjectedUse
    public let curve: OrthographicProjectedCurve

    public var startParameter: Double { original.edge.startParameter }
    public var endParameter: Double { original.edge.endParameter }
}
