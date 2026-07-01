import Foundation
import RupaCoreTypes

enum MeasurementDisplayNumberText {
    static func string(
        from value: Double,
        maximumFractionDigits: Int = 6
    ) -> String {
        guard value.isFinite else {
            return "\(value)"
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func valueString(
        fromMetersValue metersValue: Double,
        unit: LengthDisplayUnit,
        exponent: Int
    ) -> String {
        let divisor = pow(unit.metersPerUnit, Double(exponent))
        return string(from: metersValue / divisor)
    }

    static func lengthString(fromMeters meters: Double) -> String {
        "\(string(from: meters)) m"
    }
}
