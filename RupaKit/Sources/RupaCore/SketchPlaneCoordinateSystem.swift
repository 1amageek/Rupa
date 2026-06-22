import Foundation
import SwiftCAD

public struct SketchPlaneCoordinateSystem: Sendable {
    public struct Projection: Codable, Equatable, Sendable {
        public var point: Point2D
        public var depth: Double

        public init(point: Point2D, depth: Double) {
            self.point = point
            self.depth = depth
        }
    }

    public var plane: SketchPlane
    public var origin: Point3D
    public var normal: Vector3D
    public var u: Vector3D
    public var v: Vector3D

    public init(plane: SketchPlane, tolerance: Double = 1.0e-12) throws {
        self.plane = plane
        switch plane {
        case .xy:
            origin = .origin
            normal = .unitZ
            u = .unitX
            v = .unitY
        case .yz:
            origin = .origin
            normal = .unitX
            u = .unitY
            v = .unitZ
        case .zx:
            origin = .origin
            normal = .unitY
            u = .unitZ
            v = .unitX
        case .plane(let plane):
            origin = plane.origin
            normal = try plane.normal.normalized(tolerance: tolerance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            u = try helper.cross(normal).normalized(tolerance: tolerance)
            v = normal.cross(u)
        }
    }

    public func point(from localPoint: Point2D) -> Point3D {
        origin + (u * localPoint.x) + (v * localPoint.y)
    }

    public func project(_ worldPoint: Point3D) -> Projection {
        let delta = worldPoint - origin
        return Projection(
            point: Point2D(
                x: delta.dot(u),
                y: delta.dot(v)
            ),
            depth: delta.dot(normal)
        )
    }

    public func projectsParallel(to other: SketchPlaneCoordinateSystem, tolerance: Double = 1.0e-9) -> Bool {
        abs(abs(normal.dot(other.normal)) - 1.0) <= tolerance
    }
}
