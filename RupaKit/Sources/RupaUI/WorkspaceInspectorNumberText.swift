import Foundation

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
}
