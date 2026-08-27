import Foundation

/// A finite translation vector used by semantic Mesh edit operations.
public struct GeometryVector3D: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var isZero: Bool {
        x == 0 && y == 0 && z == 0
    }

    public func validate() throws {
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw MeshEditError(
                code: .nonFiniteValue,
                message: "Geometry vector components must be finite."
            )
        }
    }

    public func applying(to point: GeometryPoint3D) throws -> GeometryPoint3D {
        try validate()
        try point.validate()
        let translated = GeometryPoint3D(
            x: point.x + x,
            y: point.y + y,
            z: point.z + z
        )
        guard translated.x.isFinite,
              translated.y.isFinite,
              translated.z.isFinite else {
            throw MeshEditError(
                code: .integerOverflow,
                message: "Geometry translation exceeds the finite coordinate domain."
            )
        }
        return translated
    }
}
