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
        public var independentCopyState: PatternArraySummary.IndependentCopyOutputState?
        public var independentCopyRegenerationPolicy: PatternArraySummary.IndependentCopyRegenerationPolicy?

        public init(
            componentInstanceID: ComponentInstanceID? = nil,
            sceneNodeID: SceneNodeID,
            featureIDs: [FeatureID] = [],
            name: String,
            localTransform: Transform3D,
            isVisible: Bool,
            isLocked: Bool,
            independentCopyState: PatternArraySummary.IndependentCopyOutputState? = nil,
            independentCopyRegenerationPolicy: PatternArraySummary.IndependentCopyRegenerationPolicy? = nil
        ) {
            self.componentInstanceID = componentInstanceID
            self.sceneNodeID = sceneNodeID
            self.featureIDs = featureIDs
            self.name = name
            self.localTransform = localTransform
            self.isVisible = isVisible
            self.isLocked = isLocked
            self.independentCopyState = independentCopyState
            self.independentCopyRegenerationPolicy = independentCopyRegenerationPolicy
        }
    }

    public var sourceID: PatternArraySourceID
    public var name: String
    public var definitionID: ComponentDefinitionID
    public var definitionName: String?
    public var definitionIdentity: PatternArrayDefinitionIdentity?
    public var distribution: PatternArrayDistribution
    public var outputMode: PatternArrayOutputMode
    public var rootSceneNodeID: SceneNodeID
    public var rootSceneNodeName: String?
    public var outputCount: Int
    public var outputs: [Output]
    public var diagnostics: [PatternArraySummary.Diagnostic]

    public init(
        sourceID: PatternArraySourceID,
        name: String,
        definitionID: ComponentDefinitionID,
        definitionName: String?,
        definitionIdentity: PatternArrayDefinitionIdentity? = nil,
        distribution: PatternArrayDistribution,
        outputMode: PatternArrayOutputMode,
        rootSceneNodeID: SceneNodeID,
        rootSceneNodeName: String?,
        outputCount: Int,
        outputs: [Output],
        diagnostics: [PatternArraySummary.Diagnostic] = []
    ) {
        self.sourceID = sourceID
        self.name = name
        self.definitionID = definitionID
        self.definitionName = definitionName
        self.definitionIdentity = definitionIdentity
        self.distribution = distribution
        self.outputMode = outputMode
        self.rootSceneNodeID = rootSceneNodeID
        self.rootSceneNodeName = rootSceneNodeName
        self.outputCount = outputCount
        self.outputs = outputs
        self.diagnostics = diagnostics
    }
}
