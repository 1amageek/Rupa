public struct CanonicalQuantity: Codable, Equatable, Hashable, Sendable {
    /// Magnitude in canonical SI base units. Angles use radians.
    public let magnitude: Double
    public let dimension: QuantityDimension

    public init(magnitude: Double, dimension: QuantityDimension) throws {
        guard magnitude.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Canonical quantity magnitudes must be finite."
            )
        }
        self.magnitude = magnitude == 0 ? 0 : magnitude
        self.dimension = dimension
    }

    private enum CodingKeys: String, CodingKey {
        case magnitude
        case dimension
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            magnitude: container.decode(Double.self, forKey: .magnitude),
            dimension: container.decode(QuantityDimension.self, forKey: .dimension)
        )
    }
}
