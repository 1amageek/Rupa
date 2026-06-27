import SwiftCAD
import RupaCoreTypes

public struct PatternArrayExpressionResolver: Sendable {
    public let parameters: ParameterTable

    public init(parameters: ParameterTable) {
        self.parameters = parameters
    }

    public func lengthMeters(for expression: CADExpression) throws -> Double {
        try resolvedValue(
            for: expression,
            expectedKind: .length,
            valueDescription: "distance",
            expectedDescription: "a length"
        )
    }

    public func angleRadians(for expression: CADExpression) throws -> Double {
        try resolvedValue(
            for: expression,
            expectedKind: .angle,
            valueDescription: "angle",
            expectedDescription: "an angle"
        )
    }

    public func scalarValue(for expression: CADExpression) throws -> Double {
        try resolvedValue(
            for: expression,
            expectedKind: .scalar,
            valueDescription: "scalar value",
            expectedDescription: "a scalar"
        )
    }

    private func resolvedValue(
        for expression: CADExpression,
        expectedKind: QuantityKind,
        valueDescription: String,
        expectedDescription: String
    ) throws -> Double {
        let quantity: Quantity
        do {
            quantity = try parameters.resolvedValue(for: expression)
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array \(valueDescription) could not be resolved: \(error)."
            )
        }
        guard quantity.kind == expectedKind else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array \(valueDescription) must resolve to \(expectedDescription)."
            )
        }
        return quantity.value
    }
}
