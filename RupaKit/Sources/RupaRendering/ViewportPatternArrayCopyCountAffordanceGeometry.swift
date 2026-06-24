import CoreGraphics
import Foundation
import RupaCore

enum ViewportPatternArrayCopyCountAffordanceGeometry: Equatable {
    case linear(ViewportPatternArrayCopyCountLinearGeometry)
    case angular(ViewportPatternArrayCopyCountAngularGeometry)

    var baseCopyCount: Int {
        switch self {
        case .linear(let geometry):
            geometry.baseCopyCount
        case .angular(let geometry):
            geometry.baseCopyCount
        }
    }

    var handlePoint: CGPoint {
        switch self {
        case .linear(let geometry):
            geometry.handlePoint()
        case .angular(let geometry):
            geometry.handlePoint()
        }
    }

    func handlePoint(copyCount: Int) -> CGPoint {
        switch self {
        case .linear(let geometry):
            geometry.handlePoint(copyCount: copyCount)
        case .angular(let geometry):
            geometry.handlePoint(copyCount: copyCount)
        }
    }

    func guidePoints(copyCount: Int? = nil) -> [CGPoint] {
        switch self {
        case .linear(let geometry):
            [
                geometry.baseProjectedPoint,
                geometry.handlePoint(copyCount: copyCount ?? geometry.baseCopyCount),
            ]
        case .angular(let geometry):
            geometry.arcPoints(copyCount: copyCount ?? geometry.baseCopyCount)
        }
    }

    func copyCount(
        start: CGPoint,
        current: CGPoint
    ) -> Int {
        switch self {
        case .linear(let geometry):
            geometry.copyCount(start: start, current: current)
        case .angular(let geometry):
            geometry.copyCount(start: start, current: current)
        }
    }
}

struct ViewportPatternArrayCopyCountLinearGeometry: Equatable {
    var baseProjectedPoint: CGPoint
    var projectedDirection: CGVector
    var baseCopyCount: Int
    var pointsPerCopy: CGFloat

    init?(
        baseProjectedPoint: CGPoint,
        axisDirection: Vector3D,
        distanceMeters: Double,
        copyCount: Int,
        layout: ViewportLayout,
        minimumPointsPerCopy: CGFloat = 28.0
    ) {
        guard distanceMeters.isFinite,
              distanceMeters > 0.0,
              copyCount > 0,
              minimumPointsPerCopy.isFinite,
              minimumPointsPerCopy > 0.0 else {
            return nil
        }
        let axisLength = axisDirection.length
        guard axisLength.isFinite, axisLength > 1.0e-12 else {
            return nil
        }
        let unit = Vector3D(
            x: axisDirection.x / axisLength,
            y: axisDirection.y / axisLength,
            z: axisDirection.z / axisLength
        )
        let projected = CGVector(
            dx: (
                layout.basis.xDirection.dx * CGFloat(unit.x)
                    + layout.basis.yDirection.dx * CGFloat(unit.y)
                    + layout.basis.zDirection.dx * CGFloat(unit.z)
            ) * layout.scale,
            dy: (
                layout.basis.xDirection.dy * CGFloat(unit.x)
                    + layout.basis.yDirection.dy * CGFloat(unit.y)
                    + layout.basis.zDirection.dy * CGFloat(unit.z)
            ) * layout.scale
        )
        guard projected.length > 1.0e-9 else {
            return nil
        }
        self.baseProjectedPoint = baseProjectedPoint
        self.projectedDirection = projected.normalized
        self.baseCopyCount = copyCount
        self.pointsPerCopy = max(CGFloat(distanceMeters) * projected.length, minimumPointsPerCopy)
    }

    func handlePoint(copyCount: Int? = nil) -> CGPoint {
        let count = max(copyCount ?? baseCopyCount, 1)
        let distance = pointsPerCopy * CGFloat(count)
        return CGPoint(
            x: baseProjectedPoint.x + projectedDirection.dx * distance,
            y: baseProjectedPoint.y + projectedDirection.dy * distance
        )
    }

    func copyCount(
        start: CGPoint,
        current: CGPoint
    ) -> Int {
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let projectedDelta = delta.dx * projectedDirection.dx + delta.dy * projectedDirection.dy
        let countDelta = Int((projectedDelta / pointsPerCopy).rounded())
        return max(baseCopyCount + countDelta, 1)
    }
}

struct ViewportPatternArrayCopyCountAngularGeometry: Equatable {
    var centerModelPoint: Point3D
    var axis: Vector3D
    var radialVector: Vector3D
    var baseCopyCount: Int
    var stepAngleRadians: Double
    var layout: ViewportLayout

    init?(
        center: Point3D,
        axis: Vector3D,
        referencePoint: Point3D,
        stepAngleRadians: Double,
        copyCount: Int,
        layout: ViewportLayout,
        minimumAngleRadians: Double = PatternArrayAnglePolicy.standard.minimumAngleRadians
    ) {
        guard stepAngleRadians.isFinite,
              minimumAngleRadians.isFinite,
              minimumAngleRadians > 0.0,
              copyCount > 0,
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
        self.baseCopyCount = copyCount
        self.stepAngleRadians = Self.normalizedSignedAngleRadians(
            stepAngleRadians,
            minimumAngleRadians: minimumAngleRadians
        )
        self.layout = layout
    }

    var centerProjectedPoint: CGPoint {
        layout.project(centerModelPoint)
    }

    func handlePoint(copyCount: Int? = nil) -> CGPoint {
        projectedPoint(angleRadians: stepAngleRadians * Double(max(copyCount ?? baseCopyCount, 1)))
    }

    func arcPoints(copyCount: Int) -> [CGPoint] {
        let angle = stepAngleRadians * Double(max(copyCount, 1))
        let segments = max(Int(abs(angle) / (.pi / 18.0)), 12)
        return (0 ... segments).map { index in
            projectedPoint(angleRadians: angle * Double(index) / Double(segments))
        }
    }

    func copyCount(
        start: CGPoint,
        current: CGPoint
    ) -> Int {
        guard let startAngle = projectedAngleParameter(for: start),
              let currentAngle = projectedAngleParameter(for: current) else {
            return baseCopyCount
        }
        let delta = Self.normalizedAngleDelta(from: startAngle, to: currentAngle)
        let countDelta = Int((delta / stepAngleRadians).rounded())
        return max(baseCopyCount + countDelta, 1)
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

    private func projectedAngleParameter(for point: CGPoint) -> Double? {
        let center = centerProjectedPoint
        let delta = CGVector(dx: point.x - center.x, dy: point.y - center.y)
        guard delta.length > 1.0e-9 else {
            return nil
        }
        let radialProjection = projectedVector(radialVector)
        let tangentProjection = projectedVector(axis.cross(radialVector))
        let determinant = radialProjection.dx * tangentProjection.dy - radialProjection.dy * tangentProjection.dx
        let determinantScale = max(radialProjection.length * tangentProjection.length, 1.0)
        guard abs(determinant) > determinantScale * 1.0e-9 else {
            return nil
        }
        let cosine = (delta.dx * tangentProjection.dy - delta.dy * tangentProjection.dx) / determinant
        let sine = (radialProjection.dx * delta.dy - radialProjection.dy * delta.dx) / determinant
        guard cosine.isFinite,
              sine.isFinite,
              hypot(cosine, sine) > 1.0e-9 else {
            return nil
        }
        return atan2(sine, cosine)
    }

    private func projectedVector(_ vector: Vector3D) -> CGVector {
        let center = centerProjectedPoint
        let end = layout.project(Self.point(centerModelPoint, offsetBy: vector))
        return CGVector(dx: end.x - center.x, dy: end.y - center.y)
    }

    private static func normalizedAngleDelta(
        from start: Double,
        to end: Double
    ) -> Double {
        var delta = end - start
        while delta <= -.pi {
            delta += .pi * 2.0
        }
        while delta > .pi {
            delta -= .pi * 2.0
        }
        return delta
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
