import CoreGraphics
import RupaCore

public enum ViewportProjectionMode: Equatable, Sendable {
    case isometric
    case axisFront(ViewportCoordinateAxis)
    case orbit
}

public struct ViewportProjectionBasis: Equatable, Sendable {
    public var mode: ViewportProjectionMode
    public var xDirection: CGVector
    public var yDirection: CGVector
    public var zDirection: CGVector

    public init(
        mode: ViewportProjectionMode,
        xDirection: CGVector,
        yDirection: CGVector,
        zDirection: CGVector
    ) {
        self.mode = mode
        self.xDirection = xDirection
        self.yDirection = yDirection
        self.zDirection = zDirection
    }

    public static var isometric: ViewportProjectionBasis {
        return viewBasis(
            mode: .isometric,
            yaw: defaultOrbitYaw,
            elevation: defaultOrbitElevation
        )
    }

    public static func axisFront(_ axis: ViewportCoordinateAxis) -> ViewportProjectionBasis {
        let depth: CGFloat = 0.18
        switch axis {
        case .x:
            return ViewportProjectionBasis(
                mode: .axisFront(.x),
                xDirection: CGVector(dx: 0.0, dy: depth),
                yDirection: CGVector(dx: 0.0, dy: -1.0),
                zDirection: CGVector(dx: -1.0, dy: 0.0)
            )
        case .y:
            return ViewportProjectionBasis(
                mode: .axisFront(.y),
                xDirection: CGVector(dx: 1.0, dy: 0.0),
                yDirection: CGVector(dx: 0.0, dy: depth),
                zDirection: CGVector(dx: 0.0, dy: 1.0)
            )
        case .z:
            return ViewportProjectionBasis(
                mode: .axisFront(.z),
                xDirection: CGVector(dx: 1.0, dy: 0.0),
                yDirection: CGVector(dx: 0.0, dy: -1.0),
                zDirection: CGVector(dx: 0.0, dy: depth)
            )
        }
    }

    public static func interpolated(
        from start: ViewportProjectionBasis,
        to end: ViewportProjectionBasis,
        progress: CGFloat
    ) -> ViewportProjectionBasis {
        let clampedProgress = min(max(progress, 0.0), 1.0)
        return ViewportProjectionBasis(
            mode: clampedProgress >= 1.0 ? end.mode : start.mode,
            xDirection: CGVector.interpolate(
                from: start.xDirection,
                to: end.xDirection,
                progress: clampedProgress
            ),
            yDirection: CGVector.interpolate(
                from: start.yDirection,
                to: end.yDirection,
                progress: clampedProgress
            ),
            zDirection: CGVector.interpolate(
                from: start.zDirection,
                to: end.zDirection,
                progress: clampedProgress
            )
        )
    }

    public func orbited(by delta: CGSize) -> ViewportProjectionBasis {
        let nextYaw = orbitYaw - delta.width * Self.orbitYawSensitivity
        let nextElevation = orbitElevation + delta.height * Self.orbitElevationSensitivity

        return Self.orbit(yaw: nextYaw, elevation: nextElevation)
    }

    public static func orbit(
        yaw: CGFloat,
        elevation: CGFloat
    ) -> ViewportProjectionBasis {
        viewBasis(
            mode: .orbit,
            yaw: yaw,
            elevation: elevation
        )
    }

    public static func aligned(to plane: SketchPlane, tolerance: Double = 1.0e-12) throws -> ViewportProjectionBasis {
        let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane, tolerance: tolerance)
        let vertical = Vector3D(
            x: -coordinateSystem.v.x,
            y: -coordinateSystem.v.y,
            z: -coordinateSystem.v.z
        )
        return basis(horizontal: coordinateSystem.u, vertical: vertical)
    }

    public func endpoint(
        from origin: CGPoint,
        axis: ViewportCoordinateAxis,
        length: CGFloat
    ) -> CGPoint {
        let direction = direction(for: axis)
        return CGPoint(
            x: origin.x + direction.dx * length,
            y: origin.y + direction.dy * length
        )
    }

    public func direction(for axis: ViewportCoordinateAxis) -> CGVector {
        switch axis {
        case .x:
            xDirection
        case .y:
            yDirection
        case .z:
            zDirection
        }
    }

    public var viewNormal: Vector3D? {
        let screenX = Vector3D(
            x: Double(xDirection.dx),
            y: Double(yDirection.dx),
            z: Double(zDirection.dx)
        )
        let screenY = Vector3D(
            x: Double(xDirection.dy),
            y: Double(yDirection.dy),
            z: Double(zDirection.dy)
        )
        do {
            return try screenY.cross(screenX).normalized(tolerance: 1.0e-12)
        } catch {
            return nil
        }
    }

    private var orbitYaw: CGFloat {
        let yaw = atan2(-zDirection.dx, xDirection.dx)
        guard yaw.isFinite else {
            return Self.defaultOrbitYaw
        }
        return yaw
    }

    private var orbitElevation: CGFloat {
        let yaw = orbitYaw
        let sinYaw = sin(yaw)
        let cosYaw = cos(yaw)
        let epsilon: CGFloat = 1.0e-6
        var candidates: [CGFloat] = []

        if abs(sinYaw) > epsilon {
            candidates.append(xDirection.dy / sinYaw)
        }
        if abs(cosYaw) > epsilon {
            candidates.append(zDirection.dy / cosYaw)
        }

        let validCandidates = candidates.filter { value in
            value.isFinite
        }
        guard !validCandidates.isEmpty else {
            return Self.defaultOrbitElevation
        }
        let averageSine = validCandidates.reduce(0.0, +) / CGFloat(validCandidates.count)
        return Self.clampedOrbitElevation(asin(min(max(averageSine, -1.0), 1.0)))
    }

    private static let defaultOrbitYaw: CGFloat = .pi / 4.0
    private static let defaultOrbitElevation: CGFloat = 0.6154797086703874
    private static let minimumOrbitElevation: CGFloat = 0.08
    private static let maximumOrbitElevation: CGFloat = 1.42
    private static let orbitYawSensitivity: CGFloat = 0.008
    private static let orbitElevationSensitivity: CGFloat = 0.006

    private static func viewBasis(
        mode: ViewportProjectionMode,
        yaw: CGFloat,
        elevation: CGFloat
    ) -> ViewportProjectionBasis {
        let clampedElevation = clampedOrbitElevation(elevation)
        let elevationSine = sin(clampedElevation)
        let elevationCosine = cos(clampedElevation)
        return ViewportProjectionBasis(
            mode: mode,
            xDirection: CGVector(
                dx: cos(yaw),
                dy: elevationSine * sin(yaw)
            ),
            yDirection: CGVector(
                dx: 0.0,
                dy: -elevationCosine
            ),
            zDirection: CGVector(
                dx: -sin(yaw),
                dy: elevationSine * cos(yaw)
            )
        )
    }

    private static func basis(horizontal: Vector3D, vertical: Vector3D) -> ViewportProjectionBasis {
        ViewportProjectionBasis(
            mode: .orbit,
            xDirection: CGVector(dx: CGFloat(horizontal.x), dy: CGFloat(vertical.x)),
            yDirection: CGVector(dx: CGFloat(horizontal.y), dy: CGFloat(vertical.y)),
            zDirection: CGVector(dx: CGFloat(horizontal.z), dy: CGFloat(vertical.z))
        )
    }

    private static func clampedOrbitElevation(_ elevation: CGFloat) -> CGFloat {
        min(max(elevation, minimumOrbitElevation), maximumOrbitElevation)
    }
}

public enum ViewportCoordinateAxis: CaseIterable, Hashable, Sendable {
    case x
    case y
    case z
}

public extension CGVector {
    static func interpolate(from start: CGVector, to end: CGVector, progress: CGFloat) -> CGVector {
        CGVector(
            dx: start.dx + (end.dx - start.dx) * progress,
            dy: start.dy + (end.dy - start.dy) * progress
        )
    }

    var normalized: CGVector {
        let length = max(hypot(dx, dy), 1.0e-12)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    var length: CGFloat {
        hypot(dx, dy)
    }

    var angleDegrees: Double {
        atan2(dy, dx) * 180.0 / .pi
    }

}
