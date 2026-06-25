import ArgumentParser
import RupaCore

enum CLIExpressionParser {
    static func length(
        value: Double,
        unit: LengthDisplayUnit,
        valueName: String = "Length"
    ) throws -> CADExpression {
        guard value.isFinite else {
            throw ValidationError("\(valueName) must be finite.")
        }
        return .constant(Quantity(value: unit.meters(from: value), kind: .length))
    }

    static func angle(
        value: Double,
        unitName: String,
        valueName: String = "Angle"
    ) throws -> CADExpression {
        guard value.isFinite else {
            throw ValidationError("\(valueName) must be finite.")
        }
        guard let angleUnit = AngleUnit(rawValue: unitName) else {
            throw ValidationError("\(valueName) unit must be degree or radian.")
        }
        return .constant(.angle(value, unit: angleUnit))
    }
}
