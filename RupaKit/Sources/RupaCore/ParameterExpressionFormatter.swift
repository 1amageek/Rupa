import Foundation
import SwiftCAD

public struct ParameterExpressionFormatter {
    public init() {}

    public func format(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) -> String {
        switch expression {
        case .constant(let quantity):
            format(quantity)
        case .reference(let parameterID):
            parameters.parameters[parameterID]?.name ?? parameterID.description
        case .variable(let name, _):
            name
        case .add(let left, let right):
            binary("+", left, right, parameters)
        case .subtract(let left, let right):
            binary("-", left, right, parameters)
        case .multiply(let left, let right):
            binary("*", left, right, parameters)
        case .divide(let left, let right):
            binary("/", left, right, parameters)
        case .sin(let argument):
            "sin(\(format(argument, parameters: parameters)))"
        case .cos(let argument):
            "cos(\(format(argument, parameters: parameters)))"
        case .tan(let argument):
            "tan(\(format(argument, parameters: parameters)))"
        }
    }

    private func binary(
        _ operation: String,
        _ left: CADExpression,
        _ right: CADExpression,
        _ parameters: ParameterTable
    ) -> String {
        "(\(format(left, parameters: parameters)) \(operation) \(format(right, parameters: parameters)))"
    }

    private func format(_ quantity: Quantity) -> String {
        switch quantity.kind {
        case .length:
            "\(formatNumber(quantity.value))m"
        case .angle:
            "\(formatNumber(quantity.value))rad"
        case .scalar:
            formatNumber(quantity.value)
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}
