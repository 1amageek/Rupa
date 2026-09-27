import SwiftCAD

/// The world-space ray through a pointer position as the mounted camera casts it: where a click
/// meets a plane the viewport does not know, such as the plane of the sketch that was clicked.
public struct ViewportPickRay: Equatable, Sendable {
    public var origin: Point3D
    /// A unit vector pointing into the scene.
    public var direction: Vector3D

    public init(origin: Point3D, direction: Vector3D) {
        self.origin = origin
        self.direction = direction
    }
}
