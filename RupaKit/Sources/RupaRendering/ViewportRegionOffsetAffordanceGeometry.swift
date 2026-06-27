import CoreGraphics
import RupaViewportScene

struct ViewportRegionOffsetAffordanceGeometry: Equatable {
    var baseModelPoint: CGPoint
    var modelDirection: CGPoint
    var baseLengthMeters: CGFloat

    init?(
        points: [CGPoint],
        layout: ViewportLayout,
        viewportLength: CGFloat = 64.0
    ) {
        guard points.count >= 3 else {
            return nil
        }
        let center = Self.polygonCentroid(points)
        let basePoint = Self.basePoint(points: points, center: center, layout: layout)
        let direction = Self.normalizedDirection(from: center, to: basePoint)
        let projectedUnitLength = Self.projectedLength(
            from: basePoint,
            direction: direction,
            distance: 1.0,
            layout: layout
        )
        self.baseModelPoint = basePoint
        self.modelDirection = direction
        self.baseLengthMeters = viewportLength / max(projectedUnitLength, 1.0e-9)
    }

    func projectedTip(
        layout: ViewportLayout,
        distanceMeters: Double = 0.0
    ) -> CGPoint {
        let visualLength = baseLengthMeters + CGFloat(distanceMeters)
        return layout.project(
            CGPoint(
                x: baseModelPoint.x + modelDirection.x * visualLength,
                y: baseModelPoint.y + modelDirection.y * visualLength
            )
        )
    }

    func offsetDistance(
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double {
        let unitEnd = CGPoint(
            x: baseModelPoint.x + modelDirection.x,
            y: baseModelPoint.y + modelDirection.y
        )
        let startProjected = layout.project(baseModelPoint)
        let unitProjected = layout.project(unitEnd)
        let projectedVector = CGVector(
            dx: unitProjected.x - startProjected.x,
            dy: unitProjected.y - startProjected.y
        )
        guard projectedVector.length > 1.0e-9 else {
            return 0.0
        }
        let direction = projectedVector.normalized
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let viewportDistance = delta.dx * direction.dx + delta.dy * direction.dy
        return Double(viewportDistance / projectedVector.length)
    }

    private static func basePoint(
        points: [CGPoint],
        center: CGPoint,
        layout: ViewportLayout
    ) -> CGPoint {
        points.max { lhs, rhs in
            let lhsProjected = layout.project(lhs)
            let rhsProjected = layout.project(rhs)
            if abs(lhsProjected.x - rhsProjected.x) > 1.0e-6 {
                return lhsProjected.x < rhsProjected.x
            }
            return pointDistance(lhs, center) < pointDistance(rhs, center)
        } ?? center
    }

    private static func polygonCentroid(_ points: [CGPoint]) -> CGPoint {
        let area = signedPolygonArea(points)
        guard abs(area) > 1.0e-12 else {
            return averagePoint(points)
        }
        var x: CGFloat = 0.0
        var y: CGFloat = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let cross = current.x * next.y - next.x * current.y
            x += (current.x + next.x) * cross
            y += (current.y + next.y) * cross
        }
        let scale = 1.0 / (6.0 * area)
        return CGPoint(x: x * scale, y: y * scale)
    }

    private static func signedPolygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else {
            return 0.0
        }
        var sum: CGFloat = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            sum += current.x * next.y - next.x * current.y
        }
        return sum * 0.5
    }

    private static func averagePoint(_ points: [CGPoint]) -> CGPoint {
        guard points.isEmpty == false else {
            return .zero
        }
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = CGFloat(points.count)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private static func normalizedDirection(
        from start: CGPoint,
        to end: CGPoint
    ) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1.0e-12 else {
            return CGPoint(x: 1.0, y: 0.0)
        }
        return CGPoint(x: dx / length, y: dy / length)
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
        return pointDistance(start, end)
    }

    private static func pointDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
