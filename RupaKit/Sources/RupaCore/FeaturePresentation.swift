import SwiftCAD
import RupaCoreTypes

public struct FeaturePresentation: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    public var sceneNodeID: SceneNodeID
    public var parentSceneNodeID: SceneNodeID?
    public var name: String
    public var kind: FeaturePresentationKind
    public var isVisible: Bool
    public var isLocked: Bool
    public var localTransform: Transform3D
    public var materialID: MaterialID?

    public init(
        featureID: FeatureID,
        sceneNodeID: SceneNodeID,
        parentSceneNodeID: SceneNodeID? = nil,
        name: String,
        kind: FeaturePresentationKind,
        isVisible: Bool = true,
        isLocked: Bool = false,
        localTransform: Transform3D = .identity,
        materialID: MaterialID? = nil
    ) {
        self.featureID = featureID
        self.sceneNodeID = sceneNodeID
        self.parentSceneNodeID = parentSceneNodeID
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.localTransform = localTransform
        self.materialID = materialID
    }
}

public enum FeaturePresentationKind: Codable, Hashable, Sendable {
    case feature
    case sketch(
        typeID: ObjectTypeID?,
        geometryRole: ObjectDescriptor.GeometryRole,
        properties: ObjectPropertySet
    )
    case body(
        sourceSection: BodySourceSectionReference?,
        typeID: ObjectTypeID?,
        geometryRole: ObjectDescriptor.GeometryRole,
        properties: ObjectPropertySet
    )
}
