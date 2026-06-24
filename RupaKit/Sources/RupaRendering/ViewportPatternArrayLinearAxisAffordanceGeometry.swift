import CoreGraphics
import RupaCore

struct ViewportPatternArrayLinearAxisAffordanceGeometry: Equatable {
    var baseProjectedPoint: CGPoint
    var projectedDirection: CGVector
    var minimumLengthPoints: CGFloat
    var baseDistanceMeters: Double
    var pointsPerMeter: CGFloat
    var minimumDistanceMeters: Double

    init?(
        baseProjectedPoint: CGPoint,
        axisDirection: Vector3D,
        distanceMeters: Double,
        layout: ViewportLayout,
        viewportLength: CGFloat = 76.0,
        minimumDistanceMeters: Double = PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters
    ) {
        guard distanceMeters.isFinite,
              distanceMeters > 0.0,
              minimumDistanceMeters.isFinite,
              minimumDistanceMeters > 0.0 else {
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
        self.minimumLengthPoints = viewportLength
        self.baseDistanceMeters = max(distanceMeters, minimumDistanceMeters)
        self.pointsPerMeter = projected.length
        self.minimumDistanceMeters = minimumDistanceMeters
    }

    func projectedTip(distanceMeters: Double? = nil) -> CGPoint {
        let distance = max(distanceMeters ?? baseDistanceMeters, minimumDistanceMeters)
        let lengthPoints = max(CGFloat(distance) * pointsPerMeter, minimumLengthPoints)
        return CGPoint(
            x: baseProjectedPoint.x + projectedDirection.dx * lengthPoints,
            y: baseProjectedPoint.y + projectedDirection.dy * lengthPoints
        )
    }

    func axisDistance(
        start: CGPoint,
        current: CGPoint
    ) -> Double {
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let viewportDistance = delta.dx * projectedDirection.dx + delta.dy * projectedDirection.dy
        let modelDistance = Double(viewportDistance / pointsPerMeter)
        return max(baseDistanceMeters + modelDistance, minimumDistanceMeters)
    }
}
