import RupaCore

public enum ViewportIndependentCopyBodyDimensionKind: String, Equatable, Sendable {
    case sizeX
    case sizeZ
    case radius
}

public struct ViewportIndependentCopyBodyDimensionDragTarget: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var outputIndex: Int
    public var outputSceneNodeID: SceneNodeID
    public var featureID: FeatureID
    public var kind: ViewportIndependentCopyBodyDimensionKind
    public var value: Double

    public init(
        sourceID: PatternArraySourceID,
        outputIndex: Int,
        outputSceneNodeID: SceneNodeID,
        featureID: FeatureID,
        kind: ViewportIndependentCopyBodyDimensionKind,
        value: Double
    ) {
        self.sourceID = sourceID
        self.outputIndex = outputIndex
        self.outputSceneNodeID = outputSceneNodeID
        self.featureID = featureID
        self.kind = kind
        self.value = value
    }
}
