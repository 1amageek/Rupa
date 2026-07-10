import Foundation

public struct ValidationQuantityDimension: Codable, Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
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
                message: "Validation quantity dimensions must not be empty."
            )
        }
    }

    public static let scalar: Self = "scalar"
    public static let count: Self = "count"
    public static let length: Self = "length"
    public static let area: Self = "area"
    public static let volume: Self = "volume"
    public static let angle: Self = "angle"
    public static let ratio: Self = "ratio"
    public static let time: Self = "time"
    public static let mass: Self = "mass"
    public static let temperature: Self = "temperature"
    public static let pressure: Self = "pressure"
    public static let speed: Self = "speed"
    public static let force: Self = "force"
    public static let energy: Self = "energy"
    public static let power: Self = "power"
}
