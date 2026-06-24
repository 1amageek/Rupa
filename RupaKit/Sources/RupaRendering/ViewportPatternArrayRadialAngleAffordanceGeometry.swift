import CoreGraphics
import Foundation
import RupaCore

struct ViewportPatternArrayRadialAngleAffordanceGeometry: Equatable {
    var centerModelPoint: Point3D
    var axis: Vector3D
    var radialVector: Vector3D
    var baseAngleRadians: Double
    var minimumAngleRadians: Double
    var layout: ViewportLayout

    init?(
        center: Point3D,
        axis: Vector3D,
        referencePoint: Point3D,
        angleRadians: Double,
        layout: ViewportLayout,
        minimumAngleRadians: Double = PatternArrayAnglePolicy.standard.minimumAngleRadians
    ) {
        guard angleRadians.isFinite,
              minimumAngleRadians.isFinite,
              minimumAngleRadians > 0.0,
              let normalizedAxis = Self.normalized(axis) else {
            return nil
        }
        let rawRadialVector = Self.vector(from: center, to: referencePoint)
        let projectedRadialVector = Self.subtract(
            rawRadialVector,
            Self.scale(normalizedAxis, by: rawRadialVector.dot(normalizedAxis))
        )
        let radialVector: Vector3D
        if projectedRadialVector.length > PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters {
            radialVector = projectedRadialVector
        } else {
            radialVector = Self.fallbackRadialVector(axis: normalizedAxis)
        }
        guard radialVector.length > PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters else {
            return nil
        }
        self.centerModelPoint = center
        self.axis = normalizedAxis
        self.radialVector = radialVector
        self.baseAngleRadians = Self.normalizedSignedAngleRadians(
            angleRadians,
            minimumAngleRadians: minimumAngleRadians
        )
        self.minimumAngleRadians = minimumAngleRadians
        self.layout = layout
    }

    var centerProjectedPoint: CGPoint {
        layout.project(centerModelPoint)
    }

    var startProjectedPoint: CGPoint {
        projectedPoint(angleRadians: 0.0)
    }

    func projectedTip(angleRadians: Double? = nil) -> CGPoint {
        projectedPoint(angleRadians: angleRadians ?? baseAngleRadians)
    }

    func projectedArcPoints(angleRadians: Double? = nil) -> [CGPoint] {
        let angle = angleRadians ?? baseAngleRadians
        let segments = max(Int(abs(angle) / (.pi / 18.0)), 12)
        return (0 ... segments).map { index in
            let ratio = Double(index) / Double(segments)
            return projectedPoint(angleRadians: angle * ratio)
        }
    }

    func angleRadians(
        start: CGPoint,
        current: CGPoint
    ) -> Double {
        let center = centerProjectedPoint
        let startVector = CGVector(dx: start.x - center.x, dy: start.y - center.y)
        let currentVector = CGVector(dx: current.x - center.x, dy: current.y - center.y)
        guard startVector.length > 1.0e-9,
              currentVector.length > 1.0e-9 else {
            return baseAngleRadians
        }
        let delta = atan2(
            startVector.dx * currentVector.dy - startVector.dy * currentVector.dx,
            startVector.dx * currentVector.dx + startVector.dy * currentVector.dy
        )
        return Self.normalizedSignedAngleRadians(
            baseAngleRadians + Double(delta),
            minimumAngleRadians: minimumAngleRadians
        )
    }

    private func projectedPoint(angleRadians: Double) -> CGPoint {
        layout.project(Self.point(centerModelPoint, offsetBy: rotated(radialVector, angleRadians: angleRadians)))
    }

    private func rotated(
        _ vector: Vector3D,
        angleRadians: Double
    ) -> Vector3D {
        let cosAngle = cos(angleRadians)
        let sinAngle = sin(angleRadians)
        return Self.add(
            Self.add(
                Self.scale(vector, by: cosAngle),
                Self.scale(axis.cross(vector), by: sinAngle)
            ),
            Self.scale(axis, by: axis.dot(vector) * (1.0 - cosAngle))
        )
    }

    private static func normalized(_ vector: Vector3D) -> Vector3D? {
        guard vector.length.isFinite, vector.length > 1.0e-12 else {
            return nil
        }
        return scale(vector, by: 1.0 / vector.length)
    }

    private static func fallbackRadialVector(axis: Vector3D) -> Vector3D {
        let helper = abs(axis.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let radial = subtract(helper, scale(axis, by: helper.dot(axis)))
        guard let normalized = normalized(radial) else {
            return Vector3D.unitX
        }
        return scale(normalized, by: 0.05)
    }

    private static func normalizedSignedAngleRadians(
        _ value: Double,
        minimumAngleRadians: Double
    ) -> Double {
        guard value.isFinite else {
            return minimumAngleRadians
        }
        guard abs(value) < minimumAngleRadians else {
            return value
        }
        return value < 0.0 ? -minimumAngleRadians : minimumAngleRadians
    }

    private static func vector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(
            x: end.x - start.x,
            y: end.y - start.y,
            z: end.z - start.z
        )
    }

    private static func point(_ point: Point3D, offsetBy vector: Vector3D) -> Point3D {
        Point3D(
            x: point.x + vector.x,
            y: point.y + vector.y,
            z: point.z + vector.z
        )
    }

    private static func add(_ lhs: Vector3D, _ rhs: Vector3D) -> Vector3D {
        Vector3D(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y,
            z: lhs.z + rhs.z
        )
    }

    private static func subtract(_ lhs: Vector3D, _ rhs: Vector3D) -> Vector3D {
        Vector3D(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y,
            z: lhs.z - rhs.z
        )
    }

    private static func scale(_ vector: Vector3D, by scalar: Double) -> Vector3D {
        Vector3D(
            x: vector.x * scalar,
            y: vector.y * scalar,
            z: vector.z * scalar
        )
    }
}
