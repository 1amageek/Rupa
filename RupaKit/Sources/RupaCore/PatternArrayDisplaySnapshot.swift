import SwiftCAD

public struct PatternArrayDisplaySnapshot: Codable, Equatable, Sendable {
    public struct Output: Codable, Equatable, Sendable {
        public var componentInstanceID: ComponentInstanceID?
        public var sceneNodeID: SceneNodeID
        public var featureIDs: [FeatureID]
        public var name: String
        public var localTransform: Transform3D
        public var isVisible: Bool
        public var isLocked: Bool

        public init(
            componentInstanceID: ComponentInstanceID? = nil,
            sceneNodeID: SceneNodeID,
            featureIDs: [FeatureID] = [],
            name: String,
            localTransform: Transform3D,
            isVisible: Bool,
            isLocked: Bool
        ) {
            self.componentInstanceID = componentInstanceID
            self.sceneNodeID = sceneNodeID
            self.featureIDs = featureIDs
            self.name = name
            self.localTransform = localTransform
            self.isVisible = isVisible
            self.isLocked = isLocked
        }
    }

    public var sourceID: PatternArraySourceID
    public var name: String
    public var definitionID: ComponentDefinitionID
    public var definitionName: String
    public var distribution: PatternArrayDistribution
    public var outputMode: PatternArrayOutputMode
    public var rootSceneNodeID: SceneNodeID
    public var rootSceneNodeName: String
    public var outputCount: Int
    public var outputs: [Output]

    public init(
        sourceID: PatternArraySourceID,
        name: String,
        definitionID: ComponentDefinitionID,
        definitionName: String,
        distribution: PatternArrayDistribution,
        outputMode: PatternArrayOutputMode,
        rootSceneNodeID: SceneNodeID,
        rootSceneNodeName: String,
        outputCount: Int,
        outputs: [Output]
    ) {
        self.sourceID = sourceID
        self.name = name
        self.definitionID = definitionID
        self.definitionName = definitionName
        self.distribution = distribution
        self.outputMode = outputMode
        self.rootSceneNodeID = rootSceneNodeID
        self.rootSceneNodeName = rootSceneNodeName
        self.outputCount = outputCount
        self.outputs = outputs
    }
}
