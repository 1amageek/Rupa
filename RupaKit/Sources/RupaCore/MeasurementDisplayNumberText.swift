import Foundation
import RupaCoreTypes

enum MeasurementDisplayNumberText {
    static func string(
        from value: Double,
        maximumFractionDigits: Int = 6
    ) -> String {
        LengthDisplayText.numberString(
            from: value,
            maximumFractionDigits: maximumFractionDigits
        )
    }

    static func valueString(
        fromMetersValue metersValue: Double,
        unit: LengthDisplayUnit,
        exponent: Int
    ) -> String {
        let divisor = pow(unit.metersPerUnit, Double(exponent))
        return string(from: metersValue / divisor)
    }

    static func lengthString(
        fromMeters meters: Double,
        unit: LengthDisplayUnit = .meter
    ) -> String {
        LengthDisplayText.lengthString(fromMeters: meters, unit: unit)
    }
}
