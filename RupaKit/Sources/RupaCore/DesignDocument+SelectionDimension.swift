import Foundation
import SwiftCAD

public extension DesignDocument {
    @discardableResult
    mutating func addSelectionDimension(
        name: String? = nil,
        kind: SelectionDimensionKind,
        first: SelectionTarget,
        second: SelectionTarget,
        target: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionDimensionID {
        let resolver = SelectionDimensionTargetResolver()
        let firstReference = try resolver.reference(
            for: first,
            in: self,
            objectRegistry: objectRegistry
        )
        let secondReference = try resolver.reference(
            for: second,
            in: self,
            objectRegistry: objectRegistry
        )
        var updatedCADDocument = cadDocument
        let dimensionID: SelectionDimensionID
        do {
            dimensionID = try updatedCADDocument.addSelectionDimension(
                name: normalizedSelectionDimensionName(name),
                kind: kind,
                first: firstReference,
                second: secondReference,
                target: target
            )
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension produced an invalid CAD document: \(String(describing: error))"
            )
        }
        cadDocument = updatedCADDocument
        return dimensionID
    }

    @discardableResult
    mutating func setSelectionDimensionTarget(
        id: SelectionDimensionID,
        target: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionDimension {
        guard cadDocument.selectionDimensions.contains(where: { $0.id == id }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension target update requires an existing selection dimension."
            )
        }

        var updatedCADDocument = cadDocument
        let updatedDimension: SelectionDimension
        do {
            updatedDimension = try updatedCADDocument.setSelectionDimensionTarget(
                id: id,
                target: target
            )
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension target update produced an invalid CAD document: \(String(describing: error))"
            )
        }

        var updatedDocument = self
        updatedDocument.cadDocument = updatedCADDocument
        try updatedDocument.productMetadata.validate(
            against: updatedDocument.cadDocument,
            objectRegistry: objectRegistry
        )
        self = updatedDocument
        return updatedDimension
    }

    @discardableResult
    mutating func removeSelectionDimension(
        id: SelectionDimensionID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionDimension {
        guard cadDocument.selectionDimensions.contains(where: { $0.id == id }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension removal requires an existing selection dimension."
            )
        }

        var updatedCADDocument = cadDocument
        let removedDimension: SelectionDimension
        do {
            removedDimension = try updatedCADDocument.removeSelectionDimension(id: id)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension removal produced an invalid CAD document: \(String(describing: error))"
            )
        }

        var updatedDocument = self
        updatedDocument.cadDocument = updatedCADDocument
        try updatedDocument.productMetadata.validate(
            against: updatedDocument.cadDocument,
            objectRegistry: objectRegistry
        )
        self = updatedDocument
        return removedDimension
    }

    private func normalizedSelectionDimensionName(_ name: String?) -> String? {
        guard let name else {
            return nil
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }
}
