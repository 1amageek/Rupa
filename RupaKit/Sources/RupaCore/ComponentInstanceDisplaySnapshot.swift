import SwiftCAD

public struct ComponentInstanceDisplaySnapshot: Codable, Equatable, Sendable {
    public var instanceID: ComponentInstanceID
    public var name: String
    public var definitionID: ComponentDefinitionID
    public var definitionName: String
    public var sceneNodeIDs: [SceneNodeID]
    public var primarySceneNodeID: SceneNodeID?
    public var localTransform: Transform3D
    public var isVisible: Bool
    public var isLocked: Bool
    public var propertyCount: Int
    public var ownership: ComponentInstanceOwnershipDisplaySnapshot

    public init(
        instanceID: ComponentInstanceID,
        name: String,
        definitionID: ComponentDefinitionID,
        definitionName: String,
        sceneNodeIDs: [SceneNodeID],
        primarySceneNodeID: SceneNodeID?,
        localTransform: Transform3D,
        isVisible: Bool,
        isLocked: Bool,
        propertyCount: Int,
        ownership: ComponentInstanceOwnershipDisplaySnapshot
    ) {
        self.instanceID = instanceID
        self.name = name
        self.definitionID = definitionID
        self.definitionName = definitionName
        self.sceneNodeIDs = sceneNodeIDs
        self.primarySceneNodeID = primarySceneNodeID
        self.localTransform = localTransform
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.propertyCount = propertyCount
        self.ownership = ownership
    }
}
