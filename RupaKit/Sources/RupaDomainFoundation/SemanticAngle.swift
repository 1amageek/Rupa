public struct SemanticAngle: Sendable, Equatable, Hashable {
    public let value: Double
    public let unit: SemanticUnit

    public init(value: Double, unit: SemanticUnit) {
        self.value = value
        self.unit = unit
    }

    public var isFinite: Bool {
        value.isFinite
    }

    public var isValidUnit: Bool {
        unit == .degree
    }
}
