import RupaCoreTypes
import SwiftCAD

public struct SceneGraphNodeSnapshot: Codable, Equatable, Sendable {
    public var id: SceneNodeID
    public var name: String
    public var reference: SceneNodeReference?
    public var objectCategory: ObjectDescriptor.Category?
    public var geometryRole: ObjectDescriptor.GeometryRole?
    public var sourceFeatureID: FeatureID?
    public var childIDs: [SceneNodeID]
    public var isVisible: Bool
    public var isLocked: Bool
    public var localTransform: Transform3D
    public var materialID: MaterialID?

    public init(
        id: SceneNodeID,
        name: String,
        reference: SceneNodeReference?,
        objectCategory: ObjectDescriptor.Category?,
        geometryRole: ObjectDescriptor.GeometryRole?,
        sourceFeatureID: FeatureID?,
        childIDs: [SceneNodeID],
        isVisible: Bool,
        isLocked: Bool,
        localTransform: Transform3D,
        materialID: MaterialID?
    ) {
        self.id = id
        self.name = name
        self.reference = reference
        self.objectCategory = objectCategory
        self.geometryRole = geometryRole
        self.sourceFeatureID = sourceFeatureID
        self.childIDs = childIDs
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.localTransform = localTransform
        self.materialID = materialID
    }
}
