import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func renameSceneNode(
        id: SceneNodeID,
        name: String,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> Bool {
        let normalizedName = try normalizedMetadataName(name, owner: "Scene node")
        guard let node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node rename requires an existing scene node."
            )
        }

        let ownershipResolver = PatternArrayOwnershipResolver()
        if let sourceID = ownershipResolver.sourceID(
            containingOutputSceneNode: id,
            in: productMetadata
        ), let source = productMetadata.patternArrays[sourceID] {
            let message = source.rootSceneNodeID == id
                ? "Pattern array root names are owned by updatePatternArray."
                : "Generated pattern output scene node names are owned by the pattern source."
            throw EditorError(code: .commandInvalid, message: message)
        }

        if node.reference?.constructionPlaneID != nil {
            throw EditorError(
                code: .commandInvalid,
                message: "Saved construction plane scene nodes must be renamed through renameConstructionPlane."
            )
        }

        if node.reference?.componentInstanceID != nil ||
            node.object?.componentInstanceID != nil {
            throw EditorError(
                code: .commandInvalid,
                message: "Component instance scene nodes must be renamed through renameComponentInstance."
            )
        }

        guard node.name != normalizedName else {
            return false
        }

        var updatedMetadata = productMetadata
        updatedMetadata.sceneNodes[id]?.name = normalizedName
        try updatedMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updatedMetadata
        return true
    }

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
