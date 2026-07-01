import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createConstructionPlane(
        name: String,
        plane: SketchPlane,
        activates: Bool = true,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ConstructionPlaneSourceID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Construction plane"
        )
        guard productMetadata.constructionPlanes.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Construction plane names must be unique."
            )
        }
        try ConstructionPlaneSource.validatePlane(plane)

        let source = ConstructionPlaneSource(
            name: trimmedName,
            plane: plane
        )
        productMetadata.constructionPlanes[source.id] = source
        if activates {
            productMetadata.activeConstructionPlaneID = source.id
        }
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .constructionPlane(source.id),
            object: .construction()
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return source.id
    }

    public mutating func setActiveConstructionPlane(
        id: ConstructionPlaneSourceID?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        if let id,
           productMetadata.constructionPlanes[id] == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Active construction plane requires an existing construction plane source."
            )
        }
        productMetadata.activeConstructionPlaneID = id
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func renameConstructionPlane(
        id: ConstructionPlaneSourceID,
        name: String,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Construction plane"
        )
        guard var source = productMetadata.constructionPlanes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane rename requires an existing construction plane source."
            )
        }
        guard productMetadata.constructionPlanes.values.allSatisfy({
            $0.id == id || $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Construction plane names must be unique."
            )
        }

        source.name = trimmedName
        productMetadata.constructionPlanes[id] = source
        for (nodeID, node) in productMetadata.sceneNodes where node.reference?.constructionPlaneID == id {
            var updatedNode = node
            updatedNode.name = trimmedName
            productMetadata.sceneNodes[nodeID] = updatedNode
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setConstructionPlane(
        id: ConstructionPlaneSourceID,
        plane: SketchPlane,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var source = productMetadata.constructionPlanes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane edit requires an existing construction plane source."
            )
        }
        try ConstructionPlaneSource.validatePlane(plane)

        source.plane = plane
        productMetadata.constructionPlanes[id] = source
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    @discardableResult
    public mutating func createConstructionPlaneFromTarget(
        name: String,
        target: SelectionTarget,
        activates: Bool = true,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ConstructionPlaneSourceID {
        let plane = try ConstructionPlaneTargetResolver().plane(
            alignedTo: target,
            in: self,
            objectRegistry: objectRegistry
        )
        return try createConstructionPlane(
            name: name,
            plane: plane,
            activates: activates,
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createConstructionPlaneFromTargets(
        name: String,
        targets: [SelectionTarget],
        viewNormal: Vector3D? = nil,
        activates: Bool = true,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ConstructionPlaneSourceID {
        let plane = try ConstructionPlaneTargetResolver().plane(
            from: targets,
            in: self,
            viewNormal: viewNormal,
            objectRegistry: objectRegistry
        )
        return try createConstructionPlane(
            name: name,
            plane: plane,
            activates: activates,
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createViewAlignedConstructionPlane(
        name: String,
        origin: Point3D = .origin,
        viewNormal: Vector3D,
        activates: Bool = true,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ConstructionPlaneSourceID {
        let plane = try ConstructionPlaneViewResolver().plane(
            origin: origin,
            viewNormal: viewNormal
        )
        return try createConstructionPlane(
            name: name,
            plane: plane,
            activates: activates,
            objectRegistry: objectRegistry
        )
    }

    public var activeConstructionPlane: ConstructionPlaneSource? {
        guard let id = productMetadata.activeConstructionPlaneID else {
            return nil
        }
        return productMetadata.constructionPlanes[id]
    }
}
