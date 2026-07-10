import Foundation

public struct ValidationUnitID: Codable, Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public func validate() throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation unit IDs must not be empty."
            )
        }
    }

    public static let unitless: Self = "1"
    public static let count: Self = "count"
    public static let meter: Self = "m"
    public static let squareMeter: Self = "m2"
    public static let cubicMeter: Self = "m3"
    public static let radian: Self = "rad"
    public static let degree: Self = "deg"
    public static let percent: Self = "percent"
    public static let second: Self = "s"
    public static let kilogram: Self = "kg"
    public static let kelvin: Self = "K"
    public static let pascal: Self = "Pa"
    public static let meterPerSecond: Self = "m/s"
    public static let newton: Self = "N"
    public static let joule: Self = "J"
    public static let watt: Self = "W"
}
