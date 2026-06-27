import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setSceneNodeVisibility(
        id: SceneNodeID,
        isVisible: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node visibility requires an existing scene node."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            containingGeneratedOutputSceneNode: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node visibility is controlled by the pattern source."
            )
        }
        node.isVisible = isVisible
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setSceneNodeLock(
        id: SceneNodeID,
        isLocked: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node lock requires an existing scene node."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            containingGeneratedOutputSceneNode: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node locks are controlled by the pattern source."
            )
        }
        node.isLocked = isLocked
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setSceneNodeTransform(
        id: SceneNodeID,
        localTransform: Transform3D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node transform requires an existing scene node."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            containingOutputSceneNode: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node transforms are controlled by the pattern source."
            )
        }
        try localTransform.validate()
        node.localTransform = localTransform
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setSceneNodeMaterial(
        id: SceneNodeID,
        materialID: MaterialID?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node material requires an existing scene node."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            containingGeneratedOutputSceneNode: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node materials are controlled by the pattern source."
            )
        }
        if let materialID,
           productMetadata.materialLibrary.materials[materialID] == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node material requires an existing material."
            )
        }
        node.materialID = materialID
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }
}
