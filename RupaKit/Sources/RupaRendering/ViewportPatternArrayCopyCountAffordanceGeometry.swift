import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene

enum ViewportPatternArrayCopyCountAffordanceGeometry: Equatable {
    case linear(ViewportPatternArrayCopyCountLinearGeometry)
    case linearDensity(ViewportPatternArrayCopyCountLinearDensityGeometry)
    case angular(ViewportPatternArrayCopyCountAngularGeometry)
    case angularDensity(ViewportPatternArrayCopyCountAngularDensityGeometry)
    case curve(ViewportPatternArrayCopyCountCurveGeometry)

    var baseCopyCount: Int {
        switch self {
        case .linear(let geometry):
            geometry.baseCopyCount
        case .linearDensity(let geometry):
            geometry.baseCopyCount
        case .angular(let geometry):
            geometry.baseCopyCount
        case .angularDensity(let geometry):
            geometry.baseCopyCount
        case .curve(let geometry):
            geometry.baseCopyCount
        }
    }

    var handlePoint: CGPoint {
        switch self {
        case .linear(let geometry):
            geometry.handlePoint()
        case .linearDensity(let geometry):
            geometry.handlePoint()
        case .angular(let geometry):
            geometry.handlePoint()
        case .angularDensity(let geometry):
            geometry.handlePoint()
        case .curve(let geometry):
            geometry.handlePoint()
        }
    }

    func handlePoint(copyCount: Int) -> CGPoint {
        switch self {
        case .linear(let geometry):
            geometry.handlePoint(copyCount: copyCount)
        case .linearDensity(let geometry):
            geometry.handlePoint(copyCount: copyCount)
        case .angular(let geometry):
            geometry.handlePoint(copyCount: copyCount)
        case .angularDensity(let geometry):
            geometry.handlePoint(copyCount: copyCount)
        case .curve(let geometry):
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
        case .linearDensity(let geometry):
            geometry.guidePoints(copyCount: copyCount ?? geometry.baseCopyCount)
        case .angular(let geometry):
            geometry.arcPoints(copyCount: copyCount ?? geometry.baseCopyCount)
        case .angularDensity(let geometry):
            geometry.guidePoints(copyCount: copyCount ?? geometry.baseCopyCount)
        case .curve(let geometry):
            geometry.guidePoints(copyCount: copyCount ?? geometry.baseCopyCount)
        }
    }

    func copyCount(
        start: CGPoint,
        current: CGPoint
    ) -> Int {
        switch self {
        case .linear(let geometry):
            geometry.copyCount(start: start, current: current)
        case .linearDensity(let geometry):
            geometry.copyCount(start: start, current: current)
        case .angular(let geometry):
            geometry.copyCount(start: start, current: current)
        case .angularDensity(let geometry):
            geometry.copyCount(start: start, current: current)
        case .curve(let geometry):
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

struct ViewportPatternArrayCopyCountLinearDensityGeometry: Equatable {
    var baseProjectedPoint: CGPoint
    var extentPoint: CGPoint
    var anchorPoint: CGPoint
    var projectedDirection: CGVector
    var baseCopyCount: Int
    var pointsPerCopy: CGFloat

    init?(
        baseProjectedPoint: CGPoint,
        axisDirection: Vector3D,
        extentDistanceMeters: Double,
        copyCount: Int,
        layout: ViewportLayout,
        handleOffsetPoints: CGFloat = 24.0,
        minimumPointsPerCopy: CGFloat = 28.0
    ) {
        guard extentDistanceMeters.isFinite,
              extentDistanceMeters > 0.0,
              copyCount > 0,
              handleOffsetPoints.isFinite,
              handleOffsetPoints > 0.0,
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
        let direction = projected.normalized
        let extentPoint = CGPoint(
            x: baseProjectedPoint.x + direction.dx * CGFloat(extentDistanceMeters) * projected.length,
            y: baseProjectedPoint.y + direction.dy * CGFloat(extentDistanceMeters) * projected.length
        )
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        self.baseProjectedPoint = baseProjectedPoint
        self.extentPoint = extentPoint
        self.anchorPoint = CGPoint(
            x: extentPoint.x + normal.dx * handleOffsetPoints,
            y: extentPoint.y + normal.dy * handleOffsetPoints
        )
        self.projectedDirection = direction
        self.baseCopyCount = copyCount
        self.pointsPerCopy = minimumPointsPerCopy
    }

    func handlePoint(copyCount: Int? = nil) -> CGPoint {
        let count = max(copyCount ?? baseCopyCount, 1)
        let distance = pointsPerCopy * CGFloat(count)
        return CGPoint(
            x: anchorPoint.x + projectedDirection.dx * distance,
            y: anchorPoint.y + projectedDirection.dy * distance
        )
    }

    func guidePoints(copyCount: Int? = nil) -> [CGPoint] {
        [
            baseProjectedPoint,
            extentPoint,
            anchorPoint,
            handlePoint(copyCount: copyCount ?? baseCopyCount),
        ]
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

struct ViewportPatternArrayCopyCountAngularDensityGeometry: Equatable {
    var centerModelPoint: Point3D
    var axis: Vector3D
    var radialVector: Vector3D
    var baseCopyCount: Int
    var extentAngleRadians: Double
    var layout: ViewportLayout
    var anchorPoint: CGPoint
    var projectedDirection: CGVector
    var pointsPerCopy: CGFloat

    init?(
        center: Point3D,
        axis: Vector3D,
        referencePoint: Point3D,
        extentAngleRadians: Double,
        copyCount: Int,
        layout: ViewportLayout,
        handleOffsetPoints: CGFloat = 24.0,
        minimumPointsPerCopy: CGFloat = 28.0,
        minimumAngleRadians: Double = PatternArrayAnglePolicy.standard.minimumAngleRadians
    ) {
        guard extentAngleRadians.isFinite,
              abs(extentAngleRadians) > minimumAngleRadians,
              copyCount > 0,
              handleOffsetPoints.isFinite,
              handleOffsetPoints > 0.0,
              minimumPointsPerCopy.isFinite,
              minimumPointsPerCopy > 0.0,
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
        self.extentAngleRadians = extentAngleRadians
        self.layout = layout
        self.pointsPerCopy = minimumPointsPerCopy

        let endRadialVector = Self.rotated(radialVector, around: normalizedAxis, angleRadians: extentAngleRadians)
        let endPoint = layout.project(Self.point(center, offsetBy: endRadialVector))
        let centerPoint = layout.project(center)
        let outward = CGVector(dx: endPoint.x - centerPoint.x, dy: endPoint.y - centerPoint.y)
        guard outward.length > 1.0e-9 else {
            return nil
        }
        let tangentVector = Self.scale(
            normalizedAxis.cross(endRadialVector),
            by: extentAngleRadians < 0.0 ? -1.0 : 1.0
        )
        let projectedTangent = Self.projectedVector(
            tangentVector,
            at: Self.point(center, offsetBy: endRadialVector),
            layout: layout
        )
        guard projectedTangent.length > 1.0e-9 else {
            return nil
        }
        self.anchorPoint = CGPoint(
            x: endPoint.x + outward.normalized.dx * handleOffsetPoints,
            y: endPoint.y + outward.normalized.dy * handleOffsetPoints
        )
        self.projectedDirection = projectedTangent.normalized
    }

    func handlePoint(copyCount: Int? = nil) -> CGPoint {
        let count = max(copyCount ?? baseCopyCount, 1)
        let distance = pointsPerCopy * CGFloat(count)
        return CGPoint(
            x: anchorPoint.x + projectedDirection.dx * distance,
            y: anchorPoint.y + projectedDirection.dy * distance
        )
    }

    func guidePoints(copyCount: Int? = nil) -> [CGPoint] {
        var points = arcPoints(angleRadians: extentAngleRadians)
        points.append(anchorPoint)
        points.append(handlePoint(copyCount: copyCount ?? baseCopyCount))
        return points
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

    private func arcPoints(angleRadians: Double) -> [CGPoint] {
        let segments = max(Int(abs(angleRadians) / (.pi / 18.0)), 12)
        return (0 ... segments).map { index in
            layout.project(Self.point(
                centerModelPoint,
                offsetBy: Self.rotated(
                    radialVector,
                    around: axis,
                    angleRadians: angleRadians * Double(index) / Double(segments)
                )
            ))
        }
    }

    private static func projectedVector(
        _ vector: Vector3D,
        at origin: Point3D,
        layout: ViewportLayout
    ) -> CGVector {
        let end = Point3D(
            x: origin.x + vector.x,
            y: origin.y + vector.y,
            z: origin.z + vector.z
        )
        let startPoint = layout.project(origin)
        let endPoint = layout.project(end)
        return CGVector(dx: endPoint.x - startPoint.x, dy: endPoint.y - startPoint.y)
    }

    private static func rotated(
        _ vector: Vector3D,
        around axis: Vector3D,
        angleRadians: Double
    ) -> Vector3D {
        let cosAngle = cos(angleRadians)
        let sinAngle = sin(angleRadians)
        return add(
            add(
                scale(vector, by: cosAngle),
                scale(axis.cross(vector), by: sinAngle)
            ),
            scale(axis, by: axis.dot(vector) * (1.0 - cosAngle))
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

struct ViewportPatternArrayCopyCountCurveGeometry: Equatable {
    var pathPoints: [CGPoint]
    var anchorPoint: CGPoint
    var projectedDirection: CGVector
    var baseCopyCount: Int
    var pointsPerCopy: CGFloat

    init?(
        path: PatternArrayCurvePathGeometry,
        distributionLength: Double,
        copyCount: Int,
        layout: ViewportLayout,
        handleOffsetPoints: CGFloat = 24.0,
        minimumPointsPerCopy: CGFloat = 28.0
    ) {
        guard distributionLength.isFinite,
              distributionLength > 0.0,
              copyCount > 0,
              handleOffsetPoints.isFinite,
              handleOffsetPoints > 0.0,
              minimumPointsPerCopy.isFinite,
              minimumPointsPerCopy > 0.0,
              let extentGeometry = ViewportPatternArrayCurveExtentAffordanceGeometry(
                  path: path,
                  distributionLength: distributionLength,
                  layout: layout
              ) else {
            return nil
        }
        let pathPoints = extentGeometry.projectedExtentPoints(distanceMeters: distributionLength)
        guard let tip = pathPoints.last else {
            return nil
        }
        let direction: CGVector
        do {
            let sample = try path.sample(at: distributionLength)
            let projectedTangent = Self.projectedVector(
                sample.tangent,
                at: sample.point,
                layout: layout
            )
            if projectedTangent.length > 1.0e-9 {
                direction = projectedTangent.normalized
            } else if let fallback = Self.fallbackDirection(from: pathPoints) {
                direction = fallback
            } else {
                return nil
            }
        } catch {
            guard let fallback = Self.fallbackDirection(from: pathPoints) else {
                return nil
            }
            direction = fallback
        }
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        self.pathPoints = pathPoints
        self.anchorPoint = CGPoint(
            x: tip.x + normal.dx * handleOffsetPoints,
            y: tip.y + normal.dy * handleOffsetPoints
        )
        self.projectedDirection = direction
        self.baseCopyCount = copyCount
        self.pointsPerCopy = minimumPointsPerCopy
    }

    func handlePoint(copyCount: Int? = nil) -> CGPoint {
        let count = max(copyCount ?? baseCopyCount, 1)
        let distance = pointsPerCopy * CGFloat(count)
        return CGPoint(
            x: anchorPoint.x + projectedDirection.dx * distance,
            y: anchorPoint.y + projectedDirection.dy * distance
        )
    }

    func guidePoints(copyCount: Int? = nil) -> [CGPoint] {
        var points = pathPoints
        points.append(anchorPoint)
        points.append(handlePoint(copyCount: copyCount ?? baseCopyCount))
        return points
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

    private static func projectedVector(
        _ vector: Vector3D,
        at origin: Point3D,
        layout: ViewportLayout
    ) -> CGVector {
        let end = Point3D(
            x: origin.x + vector.x,
            y: origin.y + vector.y,
            z: origin.z + vector.z
        )
        let startPoint = layout.project(origin)
        let endPoint = layout.project(end)
        return CGVector(
            dx: endPoint.x - startPoint.x,
            dy: endPoint.y - startPoint.y
        )
    }

    private static func fallbackDirection(from points: [CGPoint]) -> CGVector? {
        guard points.count >= 2,
              let last = points.last else {
            return nil
        }
        for point in points.dropLast().reversed() {
            let direction = CGVector(dx: last.x - point.x, dy: last.y - point.y)
            if direction.length > 1.0e-9 {
                return direction.normalized
            }
        }
        return nil
    }
}
