import Foundation
import RupaCore

enum WorkspaceInspectorNumberText {
    static func string(
        from value: Double,
        maximumFractionDigits: Int = 6
    ) -> String {
        LengthDisplayText.numberString(
            from: value,
            maximumFractionDigits: maximumFractionDigits
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
        LengthDisplayText.lengthString(
            fromMeters: meters,
            unit: unit,
            maximumFractionDigits: maximumFractionDigits
        )
    }
}
