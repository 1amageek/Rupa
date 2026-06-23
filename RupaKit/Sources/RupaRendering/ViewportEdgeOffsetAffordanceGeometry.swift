import CoreGraphics

struct ViewportEdgeOffsetAffordanceGeometry: Equatable {
    var baseProjectedPoint: CGPoint
    var projectedDirection: CGVector
    var minimumLengthPoints: CGFloat
    var baseDistanceMeters: Double
    var pointsPerMeter: CGFloat

    init?(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        supportPoint: CGPoint?,
        fallbackDirection: CGVector,
        distanceMeters: Double,
        layout: ViewportLayout,
        viewportLength: CGFloat = 64.0
    ) {
        guard distanceMeters.isFinite, distanceMeters > 0.0 else {
            return nil
        }
        guard layout.scale > 1.0e-9 else {
            return nil
        }
        let midpoint = CGPoint(
            x: (edgeStart.x + edgeEnd.x) * 0.5,
            y: (edgeStart.y + edgeEnd.y) * 0.5
        )
        let supportDirection = supportPoint.map { point in
            CGVector(dx: point.x - midpoint.x, dy: point.y - midpoint.y)
        }
        let direction = (supportDirection?.normalized).flatMap { vector in
            vector.length > 1.0e-9 ? vector : nil
        } ?? fallbackDirection.normalized
        guard direction.length > 1.0e-9 else {
            return nil
        }

        self.baseProjectedPoint = midpoint
        self.projectedDirection = direction
        self.minimumLengthPoints = viewportLength
        self.baseDistanceMeters = distanceMeters
        self.pointsPerMeter = layout.scale
    }

    func projectedTip(distanceMeters: Double? = nil) -> CGPoint {
        let distance = max(distanceMeters ?? baseDistanceMeters, 1.0e-9)
        let lengthPoints = max(CGFloat(distance) * pointsPerMeter, minimumLengthPoints)
        return CGPoint(
            x: baseProjectedPoint.x + projectedDirection.dx * lengthPoints,
            y: baseProjectedPoint.y + projectedDirection.dy * lengthPoints
        )
    }

    func offsetDistance(
        start: CGPoint,
        current: CGPoint
    ) -> Double {
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let viewportDistance = delta.dx * projectedDirection.dx + delta.dy * projectedDirection.dy
        let modelDistance = Double(viewportDistance / pointsPerMeter)
        return max(baseDistanceMeters + modelDistance, 1.0e-9)
    }
}
