import RupaCore

public struct ViewportIndependentCopyExtrudeDistanceDragTarget: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var outputIndex: Int
    public var outputSceneNodeID: SceneNodeID
    public var featureID: FeatureID
    public var distance: Double

    public init(
        sourceID: PatternArraySourceID,
        outputIndex: Int,
        outputSceneNodeID: SceneNodeID,
        featureID: FeatureID,
        distance: Double
    ) {
        self.sourceID = sourceID
        self.outputIndex = outputIndex
        self.outputSceneNodeID = outputSceneNodeID
        self.featureID = featureID
        self.distance = distance
    }
}
