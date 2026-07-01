import Foundation
import RupaCore

struct ViewportLengthLabelFormatter {
    static func string(
        fromMeters meters: Double,
        preferredUnit: LengthDisplayUnit
    ) -> String {
        let unit = preferredUnit.readableUnit(forMeters: meters)
        return LengthDisplayText.lengthString(
            fromMeters: meters,
            unit: unit,
            maximumFractionDigits: maximumFractionDigits(for: unit.value(fromMeters: meters)),
            usesArchitecturalFeet: false
        )
    }

    private static func maximumFractionDigits(for value: Double) -> Int {
        let magnitude = abs(value)
        if magnitude >= 100.0 {
            return 0
        }
        if magnitude >= 10.0 {
            return 1
        }
        return 3
    }
}
