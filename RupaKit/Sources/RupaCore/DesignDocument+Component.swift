import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createComponentDefinition(
        name: String,
        rootSceneNodeIDs: [SceneNodeID] = [],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ComponentDefinitionID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Component definition"
        )
        guard productMetadata.componentDefinitions.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Component definition names must be unique."
            )
        }
        for rootSceneNodeID in rootSceneNodeIDs {
            guard productMetadata.sceneNodes[rootSceneNodeID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Component definition root scene nodes must exist."
                )
            }
            guard PatternArrayOwnershipResolver().sourceID(
                containingOutputSceneNode: rootSceneNodeID,
                in: productMetadata
            ) == nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Component definitions cannot use source-owned pattern array output scene nodes."
                )
            }
        }

        let definition = ComponentDefinition(
            name: trimmedName,
            rootSceneNodeIDs: rootSceneNodeIDs
        )
        productMetadata.componentDefinitions[definition.id] = definition
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return definition.id
    }

    @discardableResult
    public mutating func createComponentInstance(
        name: String,
        definitionID: ComponentDefinitionID,
        localTransform: Transform3D = .identity,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ComponentInstanceID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Component instance"
        )
        guard productMetadata.componentDefinitions[definitionID] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Component instances must reference an existing component definition."
            )
        }
        guard productMetadata.componentInstances.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Component instance names must be unique."
            )
        }

        let instance = ComponentInstance(
            definitionID: definitionID,
            name: trimmedName,
            localTransform: localTransform
        )
        productMetadata.componentInstances[instance.id] = instance
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .componentInstance(instance.id),
            object: .componentInstance(instance.id)
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return instance.id
    }

    public mutating func setComponentInstanceVisibility(
        id: ComponentInstanceID,
        isVisible: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Component instance visibility requires an existing component instance."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            owningOutputInstance: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output instance visibility is controlled by the pattern source."
            )
        }
        instance.isVisible = isVisible
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setComponentInstanceLock(
        id: ComponentInstanceID,
        isLocked: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Component instance lock requires an existing component instance."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            owningOutputInstance: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output instance locks are controlled by the pattern source."
            )
        }
        instance.isLocked = isLocked
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setComponentInstanceTransform(
        id: ComponentInstanceID,
        localTransform: Transform3D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Component instance transform requires an existing component instance."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            owningOutputInstance: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output instance transforms are controlled by the pattern source."
            )
        }
        try localTransform.validate()
        instance.localTransform = localTransform
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }
}
