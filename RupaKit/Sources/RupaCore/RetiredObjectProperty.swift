import RupaCoreTypes

/// A stored object property value the object type schema no longer declares.
///
/// The schema is the authority on which properties exist, so it can stop declaring one. Opening a
/// document written by an earlier schema drops the values no declared property claims, which keeps
/// the document openable. A dropped value is gone once the document is saved again, so every
/// boundary that drops one returns it instead of discarding it silently.
public struct RetiredObjectProperty: Hashable, Sendable {
    /// The scene node whose object carried the value.
    public let sceneNodeID: SceneNodeID
    /// The name of that scene node, so a report can name what changed.
    public let sceneNodeName: String
    /// The object type that stopped declaring the property.
    public let typeID: ObjectTypeID
    /// The property the object type no longer declares.
    public let propertyID: PropertyID
    /// The value the document stored for that property.
    public let value: ObjectPropertyValue

    public init(
        sceneNodeID: SceneNodeID,
        sceneNodeName: String,
        typeID: ObjectTypeID,
        propertyID: PropertyID,
        value: ObjectPropertyValue
    ) {
        self.sceneNodeID = sceneNodeID
        self.sceneNodeName = sceneNodeName
        self.typeID = typeID
        self.propertyID = propertyID
        self.value = value
    }
}
