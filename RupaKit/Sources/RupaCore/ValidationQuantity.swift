public struct ValidationQuantity: Codable, Hashable, Sendable {
    public var value: Double
    public var dimension: ValidationQuantityDimension
    public var unit: ValidationUnitID

    public init(
        value: Double,
        dimension: ValidationQuantityDimension,
        unit: ValidationUnitID
    ) {
        self.value = value
        self.dimension = dimension
        self.unit = unit
    }

    public func validate() throws {
        guard value.isFinite else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation quantity values must be finite."
            )
        }
        try dimension.validate()
        try unit.validate()
    }

    public static func scalar(_ value: Double) -> Self {
        Self(value: value, dimension: .scalar, unit: .unitless)
    }

    public static func count(_ value: Int) -> Self {
        Self(value: Double(value), dimension: .count, unit: .count)
    }

    public static func count(_ value: Double) -> Self {
        Self(value: value, dimension: .count, unit: .count)
    }

    public static func lengthMeters(_ value: Double) -> Self {
        Self(value: value, dimension: .length, unit: .meter)
    }

    public static func areaSquareMeters(_ value: Double) -> Self {
        Self(value: value, dimension: .area, unit: .squareMeter)
    }

    public static func volumeCubicMeters(_ value: Double) -> Self {
        Self(value: value, dimension: .volume, unit: .cubicMeter)
    }

    public static func angleDegrees(_ value: Double) -> Self {
        Self(value: value, dimension: .angle, unit: .degree)
    }

    public static func ratio(_ value: Double) -> Self {
        Self(value: value, dimension: .ratio, unit: .unitless)
    }
}
