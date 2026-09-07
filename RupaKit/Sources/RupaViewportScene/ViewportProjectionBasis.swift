import CoreGraphics
import RupaCore
import simd

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
        switch axis {
        case .x:
            return ViewportProjectionBasis(
                mode: .axisFront(.x),
                xDirection: CGVector(dx: 0.0, dy: 0.0),
                yDirection: CGVector(dx: 0.0, dy: -1.0),
                zDirection: CGVector(dx: -1.0, dy: 0.0)
            )
        case .y:
            return ViewportProjectionBasis(
                mode: .axisFront(.y),
                xDirection: CGVector(dx: 1.0, dy: 0.0),
                yDirection: CGVector(dx: 0.0, dy: 0.0),
                zDirection: CGVector(dx: 0.0, dy: 1.0)
            )
        case .z:
            return ViewportProjectionBasis(
                mode: .axisFront(.z),
                xDirection: CGVector(dx: 1.0, dy: 0.0),
                yDirection: CGVector(dx: 0.0, dy: -1.0),
                zDirection: CGVector(dx: 0.0, dy: 0.0)
            )
        }
    }

    public static func interpolated(
        from start: ViewportProjectionBasis,
        to end: ViewportProjectionBasis,
        progress: CGFloat
    ) -> ViewportProjectionBasis {
        guard progress.isFinite else {
            // Keep non-finite input observable as an invalid basis so the
            // layout boundary rejects it instead of publishing the start view.
            return ViewportProjectionBasis(
                mode: start.mode,
                xDirection: CGVector.interpolate(
                    from: start.xDirection,
                    to: end.xDirection,
                    progress: progress
                ),
                yDirection: CGVector.interpolate(
                    from: start.yDirection,
                    to: end.yDirection,
                    progress: progress
                ),
                zDirection: CGVector.interpolate(
                    from: start.zDirection,
                    to: end.zDirection,
                    progress: progress
                )
            )
        }
        let clampedProgress = min(max(progress, 0.0), 1.0)
        guard clampedProgress > 0.0, clampedProgress < 1.0 else {
            return clampedProgress >= 1.0 ? end : start
        }

        guard start.isRigidOrientation, end.isRigidOrientation else {
            // Preserve invalid endpoint data so the layout boundary can refuse
            // it. Invalid camera input must not be silently normalized into a
            // publishable rigid basis.
            return start.isRigidOrientation ? end : start
        }
        guard let startOrientation = start.orientation,
              var endOrientation = end.orientation else {
            return start.isRigidOrientation ? end : start
        }

        // Quaternion signs identify the same rotation. Align the endpoints
        // before slerp so the transition always takes the shortest arc.
        let quaternionDot = startOrientation.real * endOrientation.real
            + simd_dot(startOrientation.imag, endOrientation.imag)
        if quaternionDot < 0.0 {
            endOrientation = simd_quatd(
                real: -endOrientation.real,
                imag: -endOrientation.imag
            )
        }
        let orientation = simd_slerp(startOrientation, endOrientation, Double(clampedProgress))
        let matrix = simd_double3x3(orientation)
        return ViewportProjectionBasis(
            mode: start.mode,
            xDirection: CGVector(dx: matrix.columns.0.x, dy: -matrix.columns.1.x),
            yDirection: CGVector(dx: matrix.columns.0.y, dy: -matrix.columns.1.y),
            zDirection: CGVector(dx: matrix.columns.0.z, dy: -matrix.columns.1.z)
        )
    }

    public func orbited(by delta: CGSize) -> ViewportProjectionBasis {
        let nextYaw = orbitYawRadians - delta.width * Self.orbitYawSensitivity
        let nextElevation = orbitElevationRadians + delta.height * Self.orbitElevationSensitivity

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

    /// Whether the projected screen axes form a finite unit rigid frame.
    ///
    /// Invalid externally supplied frames remain observable here so the layout
    /// owner can reject them instead of silently repairing camera state.
    public var isRigidOrientation: Bool {
        let horizontal = SIMD3<Double>(
            Double(xDirection.dx),
            Double(yDirection.dx),
            Double(zDirection.dx)
        )
        let vertical = SIMD3<Double>(
            Double(xDirection.dy),
            Double(yDirection.dy),
            Double(zDirection.dy)
        )
        guard Self.isFinite(horizontal), Self.isFinite(vertical) else {
            return false
        }
        let horizontalLength = simd_length(horizontal)
        let verticalLength = simd_length(vertical)
        let normal = simd_cross(vertical, horizontal)
        let normalLength = simd_length(normal)
        guard horizontalLength.isFinite,
              verticalLength.isFinite,
              normalLength.isFinite else {
            return false
        }
        return abs(horizontalLength - 1.0) <= Self.rigidTolerance
            && abs(verticalLength - 1.0) <= Self.rigidTolerance
            && abs(simd_dot(horizontal, vertical)) <= Self.rigidTolerance
            && abs(normalLength - 1.0) <= Self.rigidTolerance
    }

    public var orbitYawRadians: CGFloat {
        let yaw = atan2(-zDirection.dx, xDirection.dx)
        guard yaw.isFinite else {
            return Self.defaultOrbitYaw
        }
        return yaw
    }

    public var orbitElevationRadians: CGFloat {
        let yaw = orbitYawRadians
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
    private static let rigidTolerance = 1.0e-10

    private var orientation: simd_quatd? {
        guard isRigidOrientation else { return nil }
        let horizontal = SIMD3<Double>(
            Double(xDirection.dx),
            Double(yDirection.dx),
            Double(zDirection.dx)
        )
        let vertical = SIMD3<Double>(
            Double(xDirection.dy),
            Double(yDirection.dy),
            Double(zDirection.dy)
        )
        let right = horizontal
        let up = -vertical
        let forward = simd_cross(right, up)
        return simd_quatd(simd_double3x3(columns: (right, up, forward)))
    }

    private static func isFinite(_ vector: SIMD3<Double>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

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

public struct ViewportCanvasPlane: Equatable, Sendable {
    public var firstAxis: ViewportCoordinateAxis
    public var secondAxis: ViewportCoordinateAxis

    public init(
        firstAxis: ViewportCoordinateAxis,
        secondAxis: ViewportCoordinateAxis
    ) {
        self.firstAxis = firstAxis
        self.secondAxis = secondAxis
    }

    public static func displayed(for basis: ViewportProjectionBasis) -> ViewportCanvasPlane {
        switch basis.mode {
        case .isometric:
            return ViewportCanvasPlane(firstAxis: .x, secondAxis: .z)
        case .axisFront(.x):
            return ViewportCanvasPlane(firstAxis: .z, secondAxis: .y)
        case .axisFront(.y):
            return ViewportCanvasPlane(firstAxis: .x, secondAxis: .z)
        case .axisFront(.z):
            return ViewportCanvasPlane(firstAxis: .x, secondAxis: .y)
        case .orbit:
            return ViewportCanvasPlane(firstAxis: .x, secondAxis: .z)
        }
    }

    public func worldPoint(first: Double, second: Double) -> Point3D {
        var point = Point3D.origin
        point.set(value: first, for: firstAxis)
        point.set(value: second, for: secondAxis)
        return point
    }

    public func direction(for axis: ViewportCoordinateAxis) -> Vector3D {
        switch axis {
        case .x:
            .unitX
        case .y:
            .unitY
        case .z:
            .unitZ
        }
    }

    public var normal: Vector3D? {
        try? direction(for: firstAxis)
            .cross(direction(for: secondAxis))
            .normalized(tolerance: 1.0e-12)
    }

    public func coordinates(of point: Point3D) -> CGPoint {
        CGPoint(
            x: CGFloat(value(of: point, for: firstAxis)),
            y: CGFloat(value(of: point, for: secondAxis))
        )
    }

    private func value(of point: Point3D, for axis: ViewportCoordinateAxis) -> Double {
        switch axis {
        case .x:
            point.x
        case .y:
            point.y
        case .z:
            point.z
        }
    }
}

private extension Point3D {
    mutating func set(value: Double, for axis: ViewportCoordinateAxis) {
        switch axis {
        case .x:
            x = value
        case .y:
            y = value
        case .z:
            z = value
        }
    }
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
