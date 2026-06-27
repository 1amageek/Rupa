import Foundation
import SwiftCAD
import RupaCoreTypes

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
    mutating func applySelectionDimensionTarget(
        id: SelectionDimensionID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionDimension {
        let originalDocument = self
        do {
            guard let dimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Selection dimension application requires an existing selection dimension."
                )
            }

            let dimension = cadDocument.selectionDimensions[dimensionIndex]
            let application = try sourceSelectionDimensionApplication(
                for: dimension,
                objectRegistry: objectRegistry
            )
            switch application {
            case .lineLength(let context):
                try setSketchEntityDimension(
                    target: context.target,
                    kind: .length,
                    value: dimension.target,
                    objectRegistry: objectRegistry
                )

                let updatedLength = try sourceLineLength(
                    featureID: context.featureID,
                    entityID: context.entityID
                )
                let updatedFirst = selectionReference(
                    curve: context.curve,
                    role: context.firstRole,
                    lineLength: updatedLength
                )
                let updatedSecond = selectionReference(
                    curve: context.curve,
                    role: context.secondRole,
                    lineLength: updatedLength
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                cadDocument.selectionDimensions[updatedDimensionIndex].first = updatedFirst
                cadDocument.selectionDimensions[updatedDimensionIndex].second = updatedSecond
                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .circularRadius(let context):
                try setSketchEntityDimension(
                    target: context.target,
                    kind: .radius,
                    value: dimension.target,
                    objectRegistry: objectRegistry
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .lineRelativeAngle(let context):
                let targetAngle = try resolvedAngle(
                    dimension.target,
                    owner: "Selection dimension application target angle"
                )
                let appliedAngle = lineAngleClosestToCurrent(
                    referenceAngle: context.referenceAngle,
                    targetAngle: targetAngle,
                    currentAngle: context.currentAngle
                )
                try setSketchEntityDimension(
                    target: context.target,
                    kind: .angle,
                    value: .angle(appliedAngle, .radian),
                    objectRegistry: objectRegistry
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .arcSpanAngle(let context):
                try setSketchEntityDimension(
                    target: context.target,
                    kind: .angle,
                    value: dimension.target,
                    objectRegistry: objectRegistry
                )
                let updatedParameters = try sourceArcEndpointParameters(
                    featureID: context.featureID,
                    entityID: context.entityID
                )
                let updatedFirst = selectionReference(
                    curve: context.curve,
                    role: context.firstRole,
                    arcEndpointParameters: updatedParameters
                )
                let updatedSecond = selectionReference(
                    curve: context.curve,
                    role: context.secondRole,
                    arcEndpointParameters: updatedParameters
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                cadDocument.selectionDimensions[updatedDimensionIndex].first = updatedFirst
                cadDocument.selectionDimensions[updatedDimensionIndex].second = updatedSecond
                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .sourcePointDistance(let context):
                try applySourcePointDistanceDimension(
                    id: id,
                    dimension: dimension,
                    context: context,
                    objectRegistry: objectRegistry
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .sourcePointLineDistance(let context):
                try applySourcePointLineDistanceDimension(
                    id: id,
                    dimension: dimension,
                    context: context,
                    objectRegistry: objectRegistry
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .objectFaceDistance(let context):
                try applyObjectFaceDistanceDimension(
                    dimension: dimension,
                    context: context,
                    objectRegistry: objectRegistry
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            }
        } catch let error as EditorError {
            self = originalDocument
            throw error
        } catch {
            self = originalDocument
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application produced an invalid document state: \(String(describing: error))"
            )
        }
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
