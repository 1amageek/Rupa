import SwiftCAD

public struct ComponentDefinitionDisplaySnapshot: Codable, Equatable, Sendable {
    public struct RootSceneNode: Codable, Equatable, Sendable {
        public var sceneNodeID: SceneNodeID
        public var name: String
        public var referenceKind: SceneNodeReference.Kind?
        public var featureID: FeatureID?
        public var componentInstanceID: ComponentInstanceID?
        public var objectCategory: ObjectDescriptor.Category?
        public var isVisible: Bool
        public var isLocked: Bool
        public var childCount: Int

        public init(
            sceneNodeID: SceneNodeID,
            name: String,
            referenceKind: SceneNodeReference.Kind?,
            featureID: FeatureID?,
            componentInstanceID: ComponentInstanceID?,
            objectCategory: ObjectDescriptor.Category?,
            isVisible: Bool,
            isLocked: Bool,
            childCount: Int
        ) {
            self.sceneNodeID = sceneNodeID
            self.name = name
            self.referenceKind = referenceKind
            self.featureID = featureID
            self.componentInstanceID = componentInstanceID
            self.objectCategory = objectCategory
            self.isVisible = isVisible
            self.isLocked = isLocked
            self.childCount = childCount
        }
    }

    public var definitionID: ComponentDefinitionID
    public var name: String
    public var rootSceneNodes: [RootSceneNode]
    public var bodySceneNodeIDs: [SceneNodeID]
    public var sketchSceneNodeIDs: [SceneNodeID]
    public var featureIDs: [FeatureID]
    public var bodyFeatureIDs: [FeatureID]
    public var sketchFeatureIDs: [FeatureID]
    public var nestedComponentInstanceIDs: [ComponentInstanceID]
    public var nestedDefinitionIDs: [ComponentDefinitionID]
    public var isRenderable: Bool

    public init(
        definitionID: ComponentDefinitionID,
        name: String,
        rootSceneNodes: [RootSceneNode],
        bodySceneNodeIDs: [SceneNodeID],
        sketchSceneNodeIDs: [SceneNodeID],
        featureIDs: [FeatureID],
        bodyFeatureIDs: [FeatureID],
        sketchFeatureIDs: [FeatureID],
        nestedComponentInstanceIDs: [ComponentInstanceID],
        nestedDefinitionIDs: [ComponentDefinitionID],
        isRenderable: Bool
    ) {
        self.definitionID = definitionID
        self.name = name
        self.rootSceneNodes = rootSceneNodes
        self.bodySceneNodeIDs = bodySceneNodeIDs
        self.sketchSceneNodeIDs = sketchSceneNodeIDs
        self.featureIDs = featureIDs
        self.bodyFeatureIDs = bodyFeatureIDs
        self.sketchFeatureIDs = sketchFeatureIDs
        self.nestedComponentInstanceIDs = nestedComponentInstanceIDs
        self.nestedDefinitionIDs = nestedDefinitionIDs
        self.isRenderable = isRenderable
    }
}
