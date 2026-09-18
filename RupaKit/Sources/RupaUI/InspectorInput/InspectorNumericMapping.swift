import SwiftUI

/// Value conversion captured at the beginning of one input interaction.
@MainActor
struct InspectorNumericMapping {
    var unit: String
    var sliderRange: ClosedRange<Double>
    var sliderValue: (Double) -> Double
    var value: (Double) -> Double
    var format: (Double) -> String
    var parse: (String) -> Double?
    var step: Double? = nil
    var editingFormat: ((Double) -> String)? = nil

    static func number(range: ClosedRange<Double>, unit: String = "") -> Self {
        Self(unit: unit, sliderRange: range,
             sliderValue: { min(max($0, range.lowerBound), range.upperBound) },
             value: { $0 }, format: WorkspaceInspectorNumberText.compact,
             parse: WorkspaceInspectorNumberText.value, editingFormat: { String($0) })
    }

    static func integer(range: ClosedRange<Double>) -> Self {
        var mapping = number(range: range)
        mapping.parse = { text in
            guard let value = WorkspaceInspectorNumberText.value(from: text),
                  Int(exactly: value.rounded()) != nil else { return nil }
            return value.rounded()
        }
        mapping.step = 1
        return mapping
    }
}
