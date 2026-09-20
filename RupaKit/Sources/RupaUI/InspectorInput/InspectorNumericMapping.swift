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

    /// A whole-number input.
    ///
    /// `step` is the distance between the values the property offers. Typed text lands on one of
    /// them, so the field never shows a number its consumer would resolve to a different one.
    static func integer(range: ClosedRange<Double>, step: Double = 1) -> Self {
        var mapping = number(range: range)
        mapping.parse = { text in
            guard let value = WorkspaceInspectorNumberText.value(from: text) else { return nil }
            let offered = step > 1
                ? range.lowerBound + ((value - range.lowerBound) / step).rounded() * step
                : value.rounded()
            guard Int(exactly: offered) != nil else { return nil }
            return offered
        }
        mapping.step = step
        return mapping
    }
}
