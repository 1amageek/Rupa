import Foundation

public enum LengthDisplayText {
    public static func numberString(
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

    public static func lengthString(
        fromMeters meters: Double,
        unit: LengthDisplayUnit,
        maximumFractionDigits: Int = 6,
        usesArchitecturalFeet: Bool = true
    ) -> String {
        if usesArchitecturalFeet, unit == .foot {
            return architecturalString(fromMeters: meters)
        }
        return "\(numberString(from: unit.value(fromMeters: meters), maximumFractionDigits: maximumFractionDigits)) \(unit.symbol)"
    }

    public static func readableLengthString(
        fromMeters meters: Double,
        preferredUnit: LengthDisplayUnit,
        maximumFractionDigits: Int = 6,
        usesArchitecturalFeet: Bool = true
    ) -> String {
        let unit = preferredUnit.readableUnit(forMeters: meters)
        return lengthString(
            fromMeters: meters,
            unit: unit,
            maximumFractionDigits: maximumFractionDigits,
            usesArchitecturalFeet: usesArchitecturalFeet
        )
    }

    public static func areaString(
        fromSquareMeters squareMeters: Double,
        unit: LengthDisplayUnit,
        maximumFractionDigits: Int = 6
    ) -> String {
        let divisor = unit.metersPerUnit * unit.metersPerUnit
        return "\(numberString(from: squareMeters / divisor, maximumFractionDigits: maximumFractionDigits)) \(unit.symbol)^2"
    }

    public static func readableAreaString(
        fromSquareMeters squareMeters: Double,
        preferredUnit: LengthDisplayUnit,
        maximumFractionDigits: Int = 6
    ) -> String {
        guard squareMeters.isFinite else {
            return areaString(
                fromSquareMeters: squareMeters,
                unit: preferredUnit,
                maximumFractionDigits: maximumFractionDigits
            )
        }
        let readableLength = sqrt(abs(squareMeters))
        let unit = preferredUnit.readableUnit(forMeters: readableLength)
        return areaString(
            fromSquareMeters: squareMeters,
            unit: unit,
            maximumFractionDigits: maximumFractionDigits
        )
    }

    public static func architecturalString(
        fromMeters meters: Double,
        denominator: Int = 16
    ) -> String {
        guard meters.isFinite else {
            return "\(meters)"
        }
        let denominator = max(1, denominator)
        let sign = meters < 0.0 ? "-" : ""
        var totalFractionUnits = Int(
            (abs(LengthDisplayUnit.inch.value(fromMeters: meters)) * Double(denominator)).rounded()
        )
        guard totalFractionUnits != 0 else {
            return "0\""
        }
        let fractionUnitsPerFoot = 12 * denominator
        let feet = totalFractionUnits / fractionUnitsPerFoot
        totalFractionUnits -= feet * fractionUnitsPerFoot
        let inches = totalFractionUnits / denominator
        let numerator = totalFractionUnits - inches * denominator
        let inchText = architecturalInchText(
            inches: inches,
            numerator: numerator,
            denominator: denominator
        )

        if feet > 0 {
            return "\(sign)\(numberString(from: Double(feet), maximumFractionDigits: 0))' \(inchText)\""
        }
        return "\(sign)\(inchText)\""
    }

    private static func architecturalInchText(
        inches: Int,
        numerator: Int,
        denominator: Int
    ) -> String {
        guard numerator != 0 else {
            return "\(inches)"
        }
        let divisor = greatestCommonDivisor(numerator, denominator)
        let reducedNumerator = numerator / divisor
        let reducedDenominator = denominator / divisor
        if inches == 0 {
            return "\(reducedNumerator)/\(reducedDenominator)"
        }
        return "\(inches) \(reducedNumerator)/\(reducedDenominator)"
    }

    private static func greatestCommonDivisor(
        _ lhs: Int,
        _ rhs: Int
    ) -> Int {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }
}
