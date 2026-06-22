import CoreGraphics

struct ViewportSketchVertexOffsetAffordanceGeometry: Equatable {
    var baseModelPoint: CGPoint
    var modelDirection: CGPoint
    var minimumLengthMeters: CGFloat
    var baseDistanceMeters: Double

    init?(
        baseModelPoint: CGPoint,
        modelDirection: CGPoint,
        distanceMeters: Double,
        layout: ViewportLayout,
        viewportLength: CGFloat = 64.0
    ) {
        guard distanceMeters.isFinite, distanceMeters > 0.0 else {
            return nil
        }
        let directionLength = hypot(modelDirection.x, modelDirection.y)
        guard directionLength > 1.0e-12 else {
            return nil
        }
        let direction = CGPoint(
            x: modelDirection.x / directionLength,
            y: modelDirection.y / directionLength
        )
        let projectedUnitLength = Self.projectedLength(
            from: baseModelPoint,
            direction: direction,
            distance: 1.0,
            layout: layout
        )
        guard projectedUnitLength > 1.0e-9 else {
            return nil
        }

        self.baseModelPoint = baseModelPoint
        self.modelDirection = direction
        self.minimumLengthMeters = viewportLength / projectedUnitLength
        self.baseDistanceMeters = distanceMeters
    }

    func projectedTip(
        layout: ViewportLayout,
        distanceMeters: Double? = nil
    ) -> CGPoint {
        let distance = max(distanceMeters ?? baseDistanceMeters, 1.0e-9)
        let lengthMeters = max(CGFloat(distance), minimumLengthMeters)
        return layout.project(
            CGPoint(
                x: baseModelPoint.x + modelDirection.x * lengthMeters,
                y: baseModelPoint.y + modelDirection.y * lengthMeters
            )
        )
    }

    func offsetDistance(
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double {
        let projectedVector = projectedUnitVector(layout: layout)
        guard projectedVector.length > 1.0e-9 else {
            return baseDistanceMeters
        }
        let direction = projectedVector.normalized
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let viewportDistance = delta.dx * direction.dx + delta.dy * direction.dy
        let modelDistance = Double(viewportDistance / projectedVector.length)
        return max(baseDistanceMeters + modelDistance, 1.0e-9)
    }

    private func projectedUnitVector(layout: ViewportLayout) -> CGVector {
        let start = layout.project(baseModelPoint)
        let end = layout.project(
            CGPoint(
                x: baseModelPoint.x + modelDirection.x,
                y: baseModelPoint.y + modelDirection.y
            )
        )
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private static func projectedLength(
        from point: CGPoint,
        direction: CGPoint,
        distance: CGFloat,
        layout: ViewportLayout
    ) -> CGFloat {
        let start = layout.project(point)
        let end = layout.project(
            CGPoint(
                x: point.x + direction.x * distance,
                y: point.y + direction.y * distance
            )
        )
        return hypot(end.x - start.x, end.y - start.y)
    }
}
