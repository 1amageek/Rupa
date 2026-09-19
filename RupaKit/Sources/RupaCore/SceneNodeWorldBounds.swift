import Foundation
import SwiftCAD

/// An axis-aligned box in world space.
///
/// Rotating a selection needs a point to turn around, and the point users expect is the middle of
/// what they selected. This is the box that middle comes from.
public struct SceneNodeWorldBounds: Equatable, Sendable {
    public var minimum: Point3D
    public var maximum: Point3D

    public init(minimum: Point3D, maximum: Point3D) {
        self.minimum = minimum
        self.maximum = maximum
    }

    /// The box enclosing `points`, or `nil` when there is nothing to enclose.
    public init?(containing points: some Sequence<Point3D>) {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else {
            return nil
        }
        var minimum = first
        var maximum = first
        while let point = iterator.next() {
            minimum = Point3D(
                x: Swift.min(minimum.x, point.x),
                y: Swift.min(minimum.y, point.y),
                z: Swift.min(minimum.z, point.z)
            )
            maximum = Point3D(
                x: Swift.max(maximum.x, point.x),
                y: Swift.max(maximum.y, point.y),
                z: Swift.max(maximum.z, point.z)
            )
        }
        self.init(minimum: minimum, maximum: maximum)
    }

    public var center: Point3D {
        Point3D(
            x: (minimum.x + maximum.x) / 2.0,
            y: (minimum.y + maximum.y) / 2.0,
            z: (minimum.z + maximum.z) / 2.0
        )
    }

    /// The eight corners, which are what a transform has to be applied to: transforming only the
    /// two extreme corners of a rotated box gives a box that no longer encloses the geometry.
    public var corners: [Point3D] {
        [
            Point3D(x: minimum.x, y: minimum.y, z: minimum.z),
            Point3D(x: maximum.x, y: minimum.y, z: minimum.z),
            Point3D(x: minimum.x, y: maximum.y, z: minimum.z),
            Point3D(x: maximum.x, y: maximum.y, z: minimum.z),
            Point3D(x: minimum.x, y: minimum.y, z: maximum.z),
            Point3D(x: maximum.x, y: minimum.y, z: maximum.z),
            Point3D(x: minimum.x, y: maximum.y, z: maximum.z),
            Point3D(x: maximum.x, y: maximum.y, z: maximum.z),
        ]
    }

    public func union(_ other: SceneNodeWorldBounds) -> SceneNodeWorldBounds {
        SceneNodeWorldBounds(
            minimum: Point3D(
                x: Swift.min(minimum.x, other.minimum.x),
                y: Swift.min(minimum.y, other.minimum.y),
                z: Swift.min(minimum.z, other.minimum.z)
            ),
            maximum: Point3D(
                x: Swift.max(maximum.x, other.maximum.x),
                y: Swift.max(maximum.y, other.maximum.y),
                z: Swift.max(maximum.z, other.maximum.z)
            )
        )
    }
}
