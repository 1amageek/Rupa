import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func upsertParameter(
        name: String,
        expression: CADExpression,
        kind: QuantityKind,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var updatedCADDocument = cadDocument
        updatedCADDocument.upsertParameter(
            name: name,
            expression: expression,
            kind: kind
        )
        cadDocument = updatedCADDocument
        do {
            try regeneratePatternArrays(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            productMetadata = previousProductMetadata
            throw error
        }
    }

    public mutating func deleteParameter(
        name: String,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard cadDocument.parameterID(named: name) != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Parameter delete requires an existing parameter."
            )
        }

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.deleteParameter(named: name)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Parameter \(name) is still referenced: \(error)."
            )
        }
        cadDocument = updatedCADDocument
        do {
            try regeneratePatternArrays(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            productMetadata = previousProductMetadata
            throw error
        }
    }
}
