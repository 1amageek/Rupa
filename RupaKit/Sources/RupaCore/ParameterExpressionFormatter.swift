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
        case .hypot(let left, let right):
            "hypot(\(format(left, parameters: parameters)), \(format(right, parameters: parameters)))"
        case .bezierNaturalExtension(let coordinates, let length, let index):
            "bezierNaturalExtension(\(index), \(format(length, parameters: parameters)), \(coordinates.map { format($0, parameters: parameters) }.joined(separator: ", ")))"
        case .bezierShapedExtension(let shape, let coordinates, let length, let index):
            shapedExtension(shape, index: index, length: length, coordinates: coordinates, parameters: parameters)
        case .sin(let argument):
            "sin(\(format(argument, parameters: parameters)))"
        case .cos(let argument):
            "cos(\(format(argument, parameters: parameters)))"
        case .tan(let argument):
            "tan(\(format(argument, parameters: parameters)))"
        }
    }

    /// `bezierArcExtension(spans, index, length, coordinates…)`, `bezierSoftExtension(…)` or
    /// `bezierReflectiveExtension(degree, coversCurve 0/1, index, length, coordinates…)`.
    private func shapedExtension(
        _ shape: BezierExtensionShape,
        index: Int,
        length: CADExpression,
        coordinates: [CADExpression],
        parameters: ParameterTable
    ) -> String {
        let head = switch shape {
        case .arc(let spanCount): "bezierArcExtension(\(spanCount)"
        case .soft(let spanCount): "bezierSoftExtension(\(spanCount)"
        case .reflective(let degree, let coversCurve): "bezierReflectiveExtension(\(degree), \(coversCurve ? 1 : 0)"
        }
        let operands = [format(length, parameters: parameters)] + coordinates.map { format($0, parameters: parameters) }
        return "\(head), \(index), \(operands.joined(separator: ", ")))"
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
