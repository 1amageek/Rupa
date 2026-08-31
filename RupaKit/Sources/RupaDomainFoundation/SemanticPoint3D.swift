public struct SemanticPoint3D: Sendable, Equatable, Hashable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let unit: SemanticUnit

    public init(x: Double, y: Double, z: Double, unit: SemanticUnit) {
        self.x = x
        self.y = y
        self.z = z
        self.unit = unit
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }

    public var isValidUnit: Bool {
        unit == .meter
    }
}
