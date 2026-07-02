import Foundation
import RupaCoreTypes

public enum DimensionSummaryValueKind: String, Codable, Equatable, Hashable, Sendable {
    case length
    case angle
    case scalar
}

public extension DimensionSummaryValueKind {
    func displayValue(
        forCanonicalValue value: Double,
        preferredLengthUnit: LengthDisplayUnit
    ) -> Double {
        switch self {
        case .length:
            readableLengthUnit(
                forMeters: value,
                preferredLengthUnit: preferredLengthUnit
            ).value(fromMeters: value)
        case .angle:
            value * 180.0 / Double.pi
        case .scalar:
            value
        }
    }

    func displayUnitSymbol(
        forCanonicalValue value: Double,
        preferredLengthUnit: LengthDisplayUnit
    ) -> String {
        switch self {
        case .length:
            readableLengthUnit(
                forMeters: value,
                preferredLengthUnit: preferredLengthUnit
            ).symbol
        case .angle:
            "deg"
        case .scalar:
            ""
        }
    }

    func readableLengthUnit(
        forMeters meters: Double,
        preferredLengthUnit: LengthDisplayUnit
    ) -> LengthDisplayUnit {
        switch self {
        case .length:
            preferredLengthUnit.readableUnit(
                forMeters: meters,
                allowsKilometers: preferredLengthUnit == .kilometer
            )
        case .angle, .scalar:
            preferredLengthUnit
        }
    }
}
