import Foundation
import SwiftCAD

public struct LengthInputParser: Sendable {
    public init() {}

    public func parseExpression(
        from text: String,
        defaultUnit: LengthDisplayUnit,
        parameters: ParameterTable = ParameterTable()
    ) throws -> CADExpression {
        let normalizedText = normalized(text)
        if let architecturalMeters = architecturalMeters(from: normalizedText) {
            return .length(
                CADInputValueNormalizer.standard.lengthMeters(architecturalMeters),
                .meter
            )
        }
        return try ParameterExpressionParser().parse(
            normalizedText,
            parameters: parameters,
            targetKind: .length,
            defaults: ParameterExpressionDefaults(lengthUnit: defaultUnit)
        )
    }

    public func parseMeters(
        from text: String,
        defaultUnit: LengthDisplayUnit,
        parameters: ParameterTable = ParameterTable()
    ) throws -> Double {
        let expression = try parseExpression(
            from: text,
            defaultUnit: defaultUnit,
            parameters: parameters
        )
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .length,
              quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Length input must resolve to a finite length."
            )
        }
        return CADInputValueNormalizer.standard.lengthMeters(quantity.value)
    }

    private func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "′", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "″", with: "\"")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
    }

    private func architecturalMeters(from text: String) -> Double? {
        var parser = ArchitecturalLengthParser(source: text)
        return parser.parseMeters()
    }
}

private struct ArchitecturalLengthParser {
    enum Unit {
        case foot
        case inch
    }

    enum Token: Equatable {
        case number(String)
        case unit(Unit)
    }

    var source: String

    mutating func parseMeters() -> Double? {
        var source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let sign: Double
        if source.hasPrefix("-") {
            sign = -1.0
            source.removeFirst()
        } else if source.hasPrefix("+") {
            sign = 1.0
            source.removeFirst()
        } else {
            sign = 1.0
        }
        guard !source.contains("+"),
              !source.contains("-"),
              !source.contains("*") else {
            return nil
        }

        let tokens = Self.tokens(from: source)
        guard tokens.contains(where: {
            if case .unit = $0 {
                return true
            }
            return false
        }) else {
            return nil
        }

        var index = 0
        var meters = 0.0
        while index < tokens.count {
            var numberTokens: [String] = []
            while index < tokens.count {
                if case .number(let value) = tokens[index] {
                    numberTokens.append(value)
                    index += 1
                } else {
                    break
                }
            }
            guard !numberTokens.isEmpty,
                  index < tokens.count,
                  case .unit(let unit) = tokens[index],
                  let value = Self.value(from: numberTokens) else {
                return nil
            }
            index += 1
            switch unit {
            case .foot:
                meters += LengthDisplayUnit.foot.meters(from: value)
            case .inch:
                meters += LengthDisplayUnit.inch.meters(from: value)
            }
        }
        return sign * meters
    }

    private static func tokens(from source: String) -> [Token] {
        var tokens: [Token] = []
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character.isWhitespace {
                source.formIndex(after: &index)
                continue
            }
            if character == "'" {
                tokens.append(.unit(.foot))
                source.formIndex(after: &index)
                continue
            }
            if character == "\"" {
                tokens.append(.unit(.inch))
                source.formIndex(after: &index)
                continue
            }
            if character.isNumber || character == "." {
                tokens.append(.number(readNumber(from: source, startingAt: &index)))
                continue
            }
            if character.isLetter {
                let word = readWord(from: source, startingAt: &index).lowercased()
                switch word {
                case "ft", "foot", "feet":
                    tokens.append(.unit(.foot))
                case "in", "inch", "inches":
                    tokens.append(.unit(.inch))
                default:
                    return []
                }
                continue
            }
            return []
        }
        return tokens
    }

    private static func readNumber(
        from source: String,
        startingAt index: inout String.Index
    ) -> String {
        let start = index
        var hasSlash = false
        while index < source.endIndex {
            let character = source[index]
            guard character.isNumber || character == "." || (character == "/" && !hasSlash) else {
                break
            }
            if character == "/" {
                hasSlash = true
            }
            source.formIndex(after: &index)
        }
        return String(source[start..<index])
    }

    private static func readWord(
        from source: String,
        startingAt index: inout String.Index
    ) -> String {
        let start = index
        while index < source.endIndex, source[index].isLetter {
            source.formIndex(after: &index)
        }
        return String(source[start..<index])
    }

    private static func value(from numberTokens: [String]) -> Double? {
        switch numberTokens.count {
        case 1:
            return value(from: numberTokens[0])
        case 2:
            guard let whole = value(from: numberTokens[0]),
                  numberTokens[1].contains("/"),
                  let fraction = value(from: numberTokens[1]) else {
                return nil
            }
            return whole + fraction
        default:
            return nil
        }
    }

    private static func value(from token: String) -> Double? {
        if token.contains("/") {
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]),
                  denominator != 0.0 else {
                return nil
            }
            return numerator / denominator
        }
        return Double(token)
    }
}
