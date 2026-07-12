import Foundation

public struct GeometryVector2D: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func validate() throws {
        guard x.isFinite, y.isFinite else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry vector components must be finite."
            )
        }
    }
}
