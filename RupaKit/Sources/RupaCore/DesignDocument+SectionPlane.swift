import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createSectionPlane(
        name: String,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SceneNodeID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Section plane"
        )
        let sceneNodeID = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .construction,
            object: .construction()
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return sceneNodeID
    }
}
