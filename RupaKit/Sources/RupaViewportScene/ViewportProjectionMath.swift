import CoreGraphics
import RupaCore

/// One affine row of the homogeneous viewport projection.
///
/// The row is evaluated against a point in the coordinate space supplied to
/// `ViewportLayout.projectionRows(relativeTo:)`. Keeping the four coefficients
/// explicit lets CPU picking and the Metal vertex path use the same math.
public struct ViewportProjectionRow: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var constant: Double

    public init(x: Double, y: Double, z: Double, constant: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.constant = constant
    }

    public func value(at point: Point3D) -> Double {
        x * point.x + y * point.y + z * point.z + constant
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && constant.isFinite
    }
}

/// The four homogeneous rows consumed by both CPU and GPU projection.
public struct ViewportProjectionRows: Equatable, Sendable {
    public var x: ViewportProjectionRow
    public var y: ViewportProjectionRow
    public var depth: ViewportProjectionRow
    public var w: ViewportProjectionRow

    public init(
        x: ViewportProjectionRow,
        y: ViewportProjectionRow,
        depth: ViewportProjectionRow,
        w: ViewportProjectionRow
    ) {
        self.x = x
        self.y = y
        self.depth = depth
        self.w = w
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && depth.isFinite && w.isFinite
    }

    public func evaluate(_ point: Point3D) -> ViewportHomogeneousPoint {
        ViewportHomogeneousPoint(
            x: x.value(at: point),
            y: y.value(at: point),
            depth: depth.value(at: point),
            w: w.value(at: point)
        )
    }
}

public struct ViewportHomogeneousPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var depth: Double
    public var w: Double

    public init(x: Double, y: Double, depth: Double, w: Double) {
        self.x = x
        self.y = y
        self.depth = depth
        self.w = w
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && depth.isFinite && w.isFinite
    }
}

/// A point that survived the homogeneous near-plane admission check.
public struct ViewportProjectedPoint: Equatable, Sendable {
    public var point: CGPoint
    public var depth: Double
    public var w: Double

    public init(point: CGPoint, depth: Double, w: Double) {
        self.point = point
        self.depth = depth
        self.w = w
    }
}

/// A world-space ray emitted by the camera through a viewport point.
public struct ViewportWorldRay: Equatable, Sendable {
    public var origin: Point3D
    public var direction: Vector3D

    public init(origin: Point3D, direction: Vector3D) {
        self.origin = origin
        self.direction = direction
    }
}
