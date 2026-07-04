import Foundation

extension DesignDocument {
    @discardableResult
    public mutating func createSavedView(
        _ savedView: SavedView,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SavedViewID {
        var updatedView = savedView
        updatedView.name = try normalizedMetadataName(
            savedView.name,
            owner: "Saved view"
        )
        guard productMetadata.savedViews[updatedView.id] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Saved view \(updatedView.id) already exists."
            )
        }
        let previousProductMetadata = productMetadata
        do {
            productMetadata.savedViews[updatedView.id] = updatedView
            try productMetadata.validate(
                against: cadDocument,
                objectRegistry: objectRegistry
            )
            return updatedView.id
        } catch {
            productMetadata = previousProductMetadata
            throw error
        }
    }

    public mutating func updateSavedView(
        _ savedView: SavedView,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        var updatedView = savedView
        updatedView.name = try normalizedMetadataName(
            savedView.name,
            owner: "Saved view"
        )
        guard productMetadata.savedViews[updatedView.id] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Saved view \(updatedView.id) does not exist."
            )
        }
        let previousProductMetadata = productMetadata
        do {
            productMetadata.savedViews[updatedView.id] = updatedView
            try productMetadata.validate(
                against: cadDocument,
                objectRegistry: objectRegistry
            )
        } catch {
            productMetadata = previousProductMetadata
            throw error
        }
    }

    public mutating func removeSavedView(
        id: SavedViewID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard productMetadata.savedViews[id] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Saved view \(id) does not exist."
            )
        }
        let previousProductMetadata = productMetadata
        do {
            productMetadata.savedViews.removeValue(forKey: id)
            try productMetadata.validate(
                against: cadDocument,
                objectRegistry: objectRegistry
            )
        } catch {
            productMetadata = previousProductMetadata
            throw error
        }
    }
}
