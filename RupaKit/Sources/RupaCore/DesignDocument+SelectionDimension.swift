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

    private func normalizedSelectionDimensionName(_ name: String?) -> String? {
        guard let name else {
            return nil
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }
}
