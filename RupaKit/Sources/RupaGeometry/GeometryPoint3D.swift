import Foundation

public struct GeometryPoint3D: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func validate() throws {
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Mesh positions must contain finite coordinates."
            )
        }
    }
}
