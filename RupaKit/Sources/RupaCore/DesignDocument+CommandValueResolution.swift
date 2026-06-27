import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func resolvedLengthValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite length."
            )
        }
        return quantity.value
    }

    func resolvedPositiveLengthValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let value = try resolvedLengthValue(expression, owner: owner)
        guard value > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be greater than zero."
            )
        }
        return value
    }

    func resolvedAngleValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to an angle."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite angle."
            )
        }
        return quantity.value
    }

    func resolvedScalarValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .scalar else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a scalar."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite scalar."
            )
        }
        return quantity.value
    }

    func resolvedPositiveScalarValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let value = try resolvedScalarValue(expression, owner: owner)
        guard value > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be greater than zero."
            )
        }
        return value
    }

    func validateSweepOptionQuantities(_ options: SweepOptions) throws {
        if let unsupportedCase = SweepEvaluationCapabilities().staticUnsupportedCase(for: options) {
            throw EditorError(
                code: .commandInvalid,
                message: unsupportedCase.message
            )
        }
        _ = try resolvedAngleValue(options.twistAngle, owner: "Sweep twist angle")
        let endScale = try resolvedScalarValue(options.endScale, owner: "Sweep end scale")
        guard endScale > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep end scale must be greater than zero."
            )
        }
        let distanceFraction = try resolvedScalarValue(
            options.distanceFraction,
            owner: "Sweep distance fraction"
        )
        guard distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep distance fraction must be greater than 0 and less than or equal to 1."
            )
        }
    }
}
