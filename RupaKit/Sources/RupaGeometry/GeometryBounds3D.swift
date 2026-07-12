import Foundation

public struct GeometryBounds3D: Codable, Equatable, Sendable {
    public var minimum: GeometryPoint3D
    public var maximum: GeometryPoint3D

    public init(minimum: GeometryPoint3D, maximum: GeometryPoint3D) throws {
        try minimum.validate()
        try maximum.validate()
        guard minimum.x <= maximum.x,
              minimum.y <= maximum.y,
              minimum.z <= maximum.z else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry bounds minimums must not exceed maximums."
            )
        }
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(points: some Sequence<GeometryPoint3D>) throws {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry bounds require at least one point."
            )
        }
        var minimum = first
        var maximum = first
        while let point = iterator.next() {
            try point.validate()
            minimum.x = min(minimum.x, point.x)
            minimum.y = min(minimum.y, point.y)
            minimum.z = min(minimum.z, point.z)
            maximum.x = max(maximum.x, point.x)
            maximum.y = max(maximum.y, point.y)
            maximum.z = max(maximum.z, point.z)
        }
        try self.init(minimum: minimum, maximum: maximum)
    }

    public func transformed(by transform: GeometryTransform3D) throws -> GeometryBounds3D {
        let points = [
            GeometryPoint3D(x: minimum.x, y: minimum.y, z: minimum.z),
            GeometryPoint3D(x: minimum.x, y: minimum.y, z: maximum.z),
            GeometryPoint3D(x: minimum.x, y: maximum.y, z: minimum.z),
            GeometryPoint3D(x: minimum.x, y: maximum.y, z: maximum.z),
            GeometryPoint3D(x: maximum.x, y: minimum.y, z: minimum.z),
            GeometryPoint3D(x: maximum.x, y: minimum.y, z: maximum.z),
            GeometryPoint3D(x: maximum.x, y: maximum.y, z: minimum.z),
            GeometryPoint3D(x: maximum.x, y: maximum.y, z: maximum.z),
        ]
        let transformedPoints = try points.map { try transform.applying(to: $0) }
        return try GeometryBounds3D(points: transformedPoints)
    }
}
