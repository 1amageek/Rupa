import Foundation
import SwiftCAD
import RupaCoreTypes

/// One of a transform frame's axes.
public enum SceneTransformAxis: String, Codable, Hashable, Sendable, CaseIterable {
    case x, y, z
}

/// Where a selection is moved from: a pivot point and a right-handed orthonormal basis.
public struct SceneTransformFrame: Codable, Hashable, Sendable {
    public private(set) var origin: Point3D
    public private(set) var xAxis: Vector3D
    public private(set) var yAxis: Vector3D
    public private(set) var zAxis: Vector3D

    /// A frame from explicit axes; they must be unit, mutually perpendicular and right-handed.
    public init(origin: Point3D, xAxis: Vector3D, yAxis: Vector3D, zAxis: Vector3D) throws {
        try origin.validate()
        let tolerance = 1.0e-9
        for axis in [xAxis, yAxis, zAxis] {
            guard axis.x.isFinite, axis.y.isFinite, axis.z.isFinite, abs(axis.length - 1) <= tolerance else {
                throw EditorError(code: .commandInvalid, message: "A transform frame needs unit axes.")
            }
        }
        guard abs(xAxis.dot(yAxis)) <= tolerance, abs(yAxis.dot(zAxis)) <= tolerance,
              abs(zAxis.dot(xAxis)) <= tolerance, xAxis.cross(yAxis).dot(zAxis) > 0 else {
            throw EditorError(code: .commandInvalid, message: "A transform frame needs perpendicular right-handed axes.")
        }
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
    }

    /// The world axes at `origin`.
    public static func world(at origin: Point3D) -> SceneTransformFrame {
        SceneTransformFrame(unchecked: origin, .unitX, .unitY, .unitZ)
    }

    /// A frame whose Z axis is `normal`; X follows the world X axis (or Y when X is nearly parallel)
    /// projected into the plane perpendicular to it.
    public init(origin: Point3D, normal: Vector3D) throws {
        let z = try normal.normalized(tolerance: 1.0e-12)
        let seed: Vector3D = abs(z.x) < 0.9 ? .unitX : .unitY
        let x = try (seed - z * seed.dot(z)).normalized(tolerance: 1.0e-12)
        try self.init(origin: origin, xAxis: x, yAxis: z.cross(x), zAxis: z)
    }

    /// A frame whose axes are the orthonormalized columns of `transform`'s linear part, at `origin`.
    public init(origin: Point3D, axesOf transform: Transform3D) throws {
        let v = transform.matrix.values
        let tolerance = 1.0e-12
        do {
            let x = try Vector3D(x: v[0], y: v[4], z: v[8]).normalized(tolerance: tolerance)
            let yRaw = Vector3D(x: v[1], y: v[5], z: v[9])
            let y = try (yRaw - x * yRaw.dot(x)).normalized(tolerance: tolerance)
            // A mirrored placement still yields a right-handed frame; handedness is not an axis.
            let z = x.cross(y)
            try self.init(origin: origin, xAxis: x, yAxis: y, zAxis: z)
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(code: .commandInvalid, message: "The object's placement has no usable axes.")
        }
    }

    private init(unchecked origin: Point3D, _ x: Vector3D, _ y: Vector3D, _ z: Vector3D) {
        self.origin = origin
        self.xAxis = x
        self.yAxis = y
        self.zAxis = z
    }

    public func axis(_ axis: SceneTransformAxis) -> Vector3D {
        switch axis {
        case .x: xAxis
        case .y: yAxis
        case .z: zAxis
        }
    }

    /// The world vector of frame components.
    public func worldVector(_ components: Vector3D) -> Vector3D {
        xAxis * components.x + yAxis * components.y + zAxis * components.z
    }

    /// The frame components of a world vector.
    public func components(of vector: Vector3D) -> Vector3D {
        Vector3D(x: vector.dot(xAxis), y: vector.dot(yAxis), z: vector.dot(zAxis))
    }

    /// The same axes at another pivot.
    public func moved(to origin: Point3D) -> SceneTransformFrame {
        SceneTransformFrame(unchecked: origin, xAxis, yAxis, zAxis)
    }
}
