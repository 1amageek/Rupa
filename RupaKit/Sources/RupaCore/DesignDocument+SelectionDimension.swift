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
        let dimension = SelectionDimension(
            name: normalizedSelectionDimensionName(name),
            kind: kind,
            first: firstReference,
            second: secondReference,
            target: target
        )
        try dimension.validate(parameters: cadDocument.parameters)

        var updatedCADDocument = cadDocument
        guard updatedCADDocument.selectionDimensions.contains(where: { $0.id == dimension.id }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension IDs must be unique."
            )
        }
        updatedCADDocument.selectionDimensions.append(dimension)
        do {
            try updatedCADDocument.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension produced an invalid CAD document: \(String(describing: error))"
            )
        }
        cadDocument = updatedCADDocument
        return dimension.id
    }

    private func normalizedSelectionDimensionName(_ name: String?) -> String? {
        guard let name else {
            return nil
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }
}
