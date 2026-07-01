import Foundation

public struct LengthInputParser: Sendable {
    public init() {}

    public func parseMeters(
        from text: String,
        defaultUnit: LengthDisplayUnit
    ) throws -> Double {
        let normalizedText = normalized(text)
        let expression = try ParameterExpressionParser().parse(
            normalizedText,
            parameters: ParameterTable(),
            targetKind: .length,
            defaults: ParameterExpressionDefaults(lengthUnit: defaultUnit)
        )
        let quantity = try ParameterTable().resolvedValue(for: expression)
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
    }
}
