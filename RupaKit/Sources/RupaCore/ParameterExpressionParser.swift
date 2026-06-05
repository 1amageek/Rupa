import Foundation
import SwiftCAD

public struct ParameterExpressionParser {
    public init() {}

    public func parse(
        _ source: String,
        parameters: ParameterTable,
        targetKind: QuantityKind,
        defaults: ParameterExpressionDefaults = ParameterExpressionDefaults()
    ) throws -> CADExpression {
        do {
            var parser = Parser(
                source: source,
                parameters: parameters,
                targetKind: targetKind,
                defaults: defaults
            )
            return try parser.parse()
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Parameter expression is invalid: \(error)."
            )
        }
    }

    public func parseForUpsert(
        _ source: String,
        parameterName: String,
        parameters: ParameterTable,
        targetKind: QuantityKind,
        defaults: ParameterExpressionDefaults = ParameterExpressionDefaults()
    ) throws -> CADExpression {
        let expression = try parse(
            source,
            parameters: parameters,
            targetKind: targetKind,
            defaults: defaults
        )
        var candidateTable = parameters
        let parameterID = candidateTable.parameters.values
            .first { $0.name == parameterName }?
            .id ?? ParameterID()
        candidateTable.parameters[parameterID] = Parameter(
            id: parameterID,
            name: parameterName,
            expression: expression,
            kind: targetKind
        )
        do {
            try candidateTable.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Parameter expression is invalid for \(parameterName): \(error)."
            )
        }
        return expression
    }

    private enum Token: Equatable {
        case number(Double, String)
        case identifier(String)
        case plus
        case minus
        case star
        case slash
        case leftParen
        case rightParen
        case end
    }

    private struct Parser {
        var tokens: [Token]
        var index = 0
        let parameters: ParameterTable
        let targetKind: QuantityKind
        let defaults: ParameterExpressionDefaults

        init(
            source: String,
            parameters: ParameterTable,
            targetKind: QuantityKind,
            defaults: ParameterExpressionDefaults
        ) {
            self.tokens = Lexer(source: source).tokens()
            self.parameters = parameters
            self.targetKind = targetKind
            self.defaults = defaults
        }

        mutating func parse() throws -> CADExpression {
            let expression = try parseExpression()
            try consume(.end, message: "Unexpected trailing tokens.")
            let normalized = normalizedSingleLiteral(expression)
            let inferredKind = try parameters.inferredKind(for: normalized)
            guard inferredKind == targetKind else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Parameter expression resolves to \(inferredKind.rawValue), but \(targetKind.rawValue) was requested."
                )
            }
            return normalized
        }

        mutating func parseExpression() throws -> CADExpression {
            try parseAddition()
        }

        mutating func parseAddition() throws -> CADExpression {
            var expression = try parseMultiplication()
            while true {
                if match(.plus) {
                    expression = .add(expression, try parseMultiplication())
                } else if match(.minus) {
                    expression = .subtract(expression, try parseMultiplication())
                } else {
                    return expression
                }
            }
        }

        mutating func parseMultiplication() throws -> CADExpression {
            var expression = try parseUnary()
            while true {
                if match(.star) {
                    expression = .multiply(expression, try parseUnary())
                } else if match(.slash) {
                    expression = .divide(expression, try parseUnary())
                } else {
                    return expression
                }
            }
        }

        mutating func parseUnary() throws -> CADExpression {
            if match(.plus) {
                return try parseUnary()
            }
            if match(.minus) {
                return .multiply(
                    .constant(.scalar(-1.0)),
                    try parseUnary()
                )
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> CADExpression {
            switch advance() {
            case .number(let value, _):
                if case .identifier(let unitName) = peek(),
                   let quantity = quantity(value, unitName: unitName) {
                    _ = advance()
                    return .constant(quantity)
                }
                if case .identifier(let unitName) = peek() {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Unsupported unit '\(unitName)'."
                    )
                }
                return .constant(.scalar(value))
            case .identifier(let name):
                if match(.leftParen) {
                    let argument = try parseExpression()
                    try consume(.rightParen, message: "Expected ')' after \(name) argument.")
                    switch name {
                    case "sin":
                        return .sin(argument)
                    case "cos":
                        return .cos(argument)
                    case "tan":
                        return .tan(argument)
                    default:
                        throw EditorError(
                            code: .commandInvalid,
                            message: "Unsupported function '\(name)'."
                        )
                    }
                }
                guard let parameterID = parameterID(named: name) else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Unknown parameter '\(name)'."
                    )
                }
                return .reference(parameterID)
            case .leftParen:
                let expression = try parseExpression()
                try consume(.rightParen, message: "Expected ')' after expression.")
                return expression
            case .end:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Parameter expression is empty."
                )
            default:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Expected a number, parameter name, function, or parenthesized expression."
                )
            }
        }

        func normalizedSingleLiteral(_ expression: CADExpression) -> CADExpression {
            guard case .constant(let quantity) = expression,
                  quantity.kind == .scalar,
                  targetKind != .scalar else {
                return expression
            }
            switch targetKind {
            case .length:
                return .constant(
                    Quantity(
                        value: defaults.lengthUnit.meters(from: quantity.value),
                        kind: .length
                    )
                )
            case .angle:
                return .constant(.angle(quantity.value, unit: defaults.angleUnit))
            case .scalar:
                return expression
            }
        }

        func quantity(_ value: Double, unitName: String) -> Quantity? {
            switch unitName {
            case "um", "micrometer", "micrometers", "micron", "microns", "μm":
                Quantity(value: LengthDisplayUnit.micrometer.meters(from: value), kind: .length)
            case "mm", "millimeter", "millimeters":
                .length(value, unit: .millimeter)
            case "cm", "centimeter", "centimeters":
                .length(value, unit: .centimeter)
            case "m", "meter", "meters":
                .length(value, unit: .meter)
            case "in", "inch", "inches":
                .length(value, unit: .inch)
            case "ft", "foot", "feet":
                .length(value, unit: .foot)
            case "rad", "radian", "radians":
                .angle(value, unit: .radian)
            case "deg", "degree", "degrees":
                .angle(value, unit: .degree)
            default:
                nil
            }
        }

        func parameterID(named name: String) -> ParameterID? {
            parameters.parameters.values.first { $0.name == name }?.id
        }

        func peek() -> Token {
            tokens[index]
        }

        mutating func advance() -> Token {
            let token = tokens[index]
            if token != .end {
                index += 1
            }
            return token
        }

        mutating func match(_ token: Token) -> Bool {
            guard peek() == token else {
                return false
            }
            _ = advance()
            return true
        }

        mutating func consume(_ token: Token, message: String) throws {
            guard match(token) else {
                throw EditorError(code: .commandInvalid, message: message)
            }
        }
    }

    private struct Lexer {
        let source: String

        func tokens() -> [Token] {
            var result: [Token] = []
            var index = source.startIndex
            while index < source.endIndex {
                let character = source[index]
                if character.isWhitespace {
                    source.formIndex(after: &index)
                    continue
                }
                switch character {
                case "+":
                    result.append(.plus)
                    source.formIndex(after: &index)
                case "-":
                    result.append(.minus)
                    source.formIndex(after: &index)
                case "*":
                    result.append(.star)
                    source.formIndex(after: &index)
                case "/":
                    result.append(.slash)
                    source.formIndex(after: &index)
                case "(":
                    result.append(.leftParen)
                    source.formIndex(after: &index)
                case ")":
                    result.append(.rightParen)
                    source.formIndex(after: &index)
                default:
                    if character.isNumber || character == "." {
                        result.append(readNumber(startingAt: &index))
                    } else {
                        result.append(readIdentifier(startingAt: &index))
                    }
                }
            }
            result.append(.end)
            return result
        }

        func readNumber(startingAt index: inout String.Index) -> Token {
            let start = index
            consumeDigits(&index)
            if index < source.endIndex, source[index] == "." {
                source.formIndex(after: &index)
                consumeDigits(&index)
            }
            if index < source.endIndex, source[index] == "e" || source[index] == "E" {
                let exponentStart = index
                source.formIndex(after: &index)
                if index < source.endIndex, source[index] == "+" || source[index] == "-" {
                    source.formIndex(after: &index)
                }
                let digitStart = index
                consumeDigits(&index)
                if digitStart == index {
                    index = exponentStart
                }
            }
            let text = String(source[start..<index])
            return .number(Double(text) ?? .nan, text)
        }

        func readIdentifier(startingAt index: inout String.Index) -> Token {
            let start = index
            while index < source.endIndex {
                let character = source[index]
                guard character.isLetter || character.isNumber || character == "_" || character == "μ" else {
                    break
                }
                source.formIndex(after: &index)
            }
            if start == index {
                source.formIndex(after: &index)
            }
            return .identifier(String(source[start..<index]))
        }

        func consumeDigits(_ index: inout String.Index) {
            while index < source.endIndex, source[index].isNumber {
                source.formIndex(after: &index)
            }
        }
    }
}
