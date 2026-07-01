import Foundation
import RupaCore

enum WorkspaceInspectorNumberText {
    static func string(
        from value: Double,
        maximumFractionDigits: Int = 6
    ) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...maximumFractionDigits))
        )
    }

    static func value(from text: String) -> Double? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }
        let normalizedText = trimmedText
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalizedText),
              value.isFinite else {
            return nil
        }
        return value
    }

    static func lengthString(
        fromMeters meters: Double,
        unit: LengthDisplayUnit,
        maximumFractionDigits: Int = 4
    ) -> String {
        let value = unit.value(fromMeters: meters)
        return "\(string(from: value, maximumFractionDigits: maximumFractionDigits)) \(unit.symbol)"
    }
}
