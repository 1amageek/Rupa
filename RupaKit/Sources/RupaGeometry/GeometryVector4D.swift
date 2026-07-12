import Foundation

public struct GeometryVector4D: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public func validate() throws {
        guard x.isFinite, y.isFinite, z.isFinite, w.isFinite else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry vector components must be finite."
            )
        }
    }
}
