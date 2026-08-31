public struct SemanticDirection3D: Sendable, Equatable, Hashable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }

    public var isNonZero: Bool {
        x != 0 || y != 0 || z != 0
    }
}
