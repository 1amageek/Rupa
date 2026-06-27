import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportSplineControlPointSlideAffordanceGeometry: Equatable {
    var baseModelPoint: CGPoint
    var modelDirection: CGPoint
    var minimumLengthMeters: CGFloat

    init?(
        controlPoints: [CGPoint],
        selectedIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        layout: ViewportLayout,
        viewportLength: CGFloat = 62.0
    ) {
        let uniqueIndexes = Self.uniqueIndexes(selectedIndexes)
        guard uniqueIndexes.isEmpty == false,
              uniqueIndexes.allSatisfy({ controlPoints.indices.contains($0) }) else {
            return nil
        }
        guard let positiveU = Self.averagePositiveUDirection(
            controlPoints: controlPoints,
            selectedIndexes: uniqueIndexes
        ) else {
            return nil
        }
        let directionVector = Self.directionVector(positiveU: positiveU, direction: direction)
        let center = Self.averagePoint(uniqueIndexes.map { controlPoints[$0] })
        let projectedUnitLength = Self.projectedLength(
            from: center,
            direction: directionVector,
            distance: 1.0,
            layout: layout
        )
        guard projectedUnitLength > 1.0e-9 else {
            return nil
        }
        self.baseModelPoint = center
        self.modelDirection = directionVector
        self.minimumLengthMeters = viewportLength / projectedUnitLength
    }

    func projectedTip(
        layout: ViewportLayout,
        distanceMeters: Double? = nil
    ) -> CGPoint {
        let distance = CGFloat(distanceMeters ?? 0.0)
        let length = abs(distance) > 1.0e-12 ? distance : minimumLengthMeters
        return layout.project(
            CGPoint(
                x: baseModelPoint.x + modelDirection.x * length,
                y: baseModelPoint.y + modelDirection.y * length
            )
        )
    }

    func slideDistance(
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double {
        let projectedVector = projectedUnitVector(layout: layout)
        guard projectedVector.length > 1.0e-9 else {
            return 0.0
        }
        let direction = projectedVector.normalized
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let viewportDistance = delta.dx * direction.dx + delta.dy * direction.dy
        return Double(viewportDistance / projectedVector.length)
    }

    static func previewControlPoints(
        controlPoints: [CGPoint],
        selectedIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        distanceMeters: Double
    ) -> [CGPoint]? {
        let uniqueIndexes = Self.uniqueIndexes(selectedIndexes)
        guard uniqueIndexes.isEmpty == false,
              uniqueIndexes.allSatisfy({ controlPoints.indices.contains($0) }) else {
            return nil
        }

        let distance = CGFloat(distanceMeters)
        var updatedControlPoints = controlPoints
        for index in uniqueIndexes {
            guard let positiveU = Self.positiveUDirection(
                controlPoints: controlPoints,
                index: index
            ) else {
                return nil
            }
            let vector = Self.directionVector(positiveU: positiveU, direction: direction)
            updatedControlPoints[index].x += vector.x * distance
            updatedControlPoints[index].y += vector.y * distance
        }
        return updatedControlPoints
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

    private static func averagePositiveUDirection(
        controlPoints: [CGPoint],
        selectedIndexes: [Int]
    ) -> CGPoint? {
        var sum = CGPoint.zero
        for index in selectedIndexes {
            guard let direction = positiveUDirection(controlPoints: controlPoints, index: index) else {
                return nil
            }
            sum.x += direction.x
            sum.y += direction.y
        }
        if let averagedDirection = normalized(sum) {
            return averagedDirection
        }
        return positiveUDirection(controlPoints: controlPoints, index: selectedIndexes[0])
    }

    private static func positiveUDirection(
        controlPoints: [CGPoint],
        index: Int
    ) -> CGPoint? {
        guard controlPoints.count >= 2,
              controlPoints.indices.contains(index) else {
            return nil
        }
        if index == controlPoints.startIndex {
            return normalized(
                CGPoint(
                    x: controlPoints[index + 1].x - controlPoints[index].x,
                    y: controlPoints[index + 1].y - controlPoints[index].y
                )
            )
        }
        if index == controlPoints.index(before: controlPoints.endIndex) {
            return normalized(
                CGPoint(
                    x: controlPoints[index].x - controlPoints[index - 1].x,
                    y: controlPoints[index].y - controlPoints[index - 1].y
                )
            )
        }
        return normalized(
            CGPoint(
                x: controlPoints[index + 1].x - controlPoints[index - 1].x,
                y: controlPoints[index + 1].y - controlPoints[index - 1].y
            )
        )
    }

    private static func directionVector(
        positiveU: CGPoint,
        direction: SplineControlPointSlideDirection
    ) -> CGPoint {
        switch direction {
        case .positiveU:
            return positiveU
        case .negativeU:
            return CGPoint(x: -positiveU.x, y: -positiveU.y)
        case .normal:
            return CGPoint(x: -positiveU.y, y: positiveU.x)
        }
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

    private static func normalized(_ vector: CGPoint) -> CGPoint? {
        let length = hypot(vector.x, vector.y)
        guard length > 1.0e-12 else {
            return nil
        }
        return CGPoint(x: vector.x / length, y: vector.y / length)
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

    private static func uniqueIndexes(_ indexes: [Int]) -> [Int] {
        var result: [Int] = []
        var seen: Set<Int> = []
        for index in indexes {
            guard seen.insert(index).inserted else {
                continue
            }
            result.append(index)
        }
        return result
    }
}
