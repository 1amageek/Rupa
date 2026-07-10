import Foundation

public struct ManufacturingProcessID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public func validate() throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManufacturingProcessCatalogError(
                code: .invalidProfile,
                message: "Manufacturing process IDs must not be empty."
            )
        }
    }

    public static let materialExtrusion: ManufacturingProcessID = "additive.materialExtrusion"
    public static let vatPhotopolymerization: ManufacturingProcessID = "additive.vatPhotopolymerization"
    public static let powderBedFusion: ManufacturingProcessID = "additive.powderBedFusion"
}
