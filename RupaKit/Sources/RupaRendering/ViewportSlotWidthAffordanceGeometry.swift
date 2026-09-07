import CoreGraphics
import RupaViewportScene

struct ViewportSlotWidthAffordanceGeometry: Equatable {
    var baseModelPoint: CGPoint
    var modelDirection: CGPoint
    var minimumLengthMeters: CGFloat
    var baseWidthMeters: Double

    init?(
        baseModelPoint: CGPoint,
        modelDirection: CGPoint,
        widthMeters: Double,
        layout: ViewportLayout,
        viewportLength: CGFloat = 64.0
    ) {
        guard widthMeters.isFinite, widthMeters > 0.0 else {
            return nil
        }
        let directionLength = hypot(modelDirection.x, modelDirection.y)
        guard directionLength > 1.0e-12 else {
            return nil
        }

        var direction = CGPoint(
            x: modelDirection.x / directionLength,
            y: modelDirection.y / directionLength
        )
        guard let shouldFlip = Self.shouldFlipDirection(
            from: baseModelPoint,
            direction: direction,
            layout: layout
        ) else {
            return nil
        }
        if shouldFlip {
            direction = CGPoint(x: -direction.x, y: -direction.y)
        }
        guard let projectedUnitLength = Self.projectedLength(
            from: baseModelPoint,
            direction: direction,
            distance: 1.0,
            layout: layout
        ) else {
            return nil
        }
        guard projectedUnitLength > 1.0e-9 else {
            return nil
        }

        self.baseModelPoint = baseModelPoint
        self.modelDirection = direction
        self.minimumLengthMeters = viewportLength / projectedUnitLength
        self.baseWidthMeters = widthMeters
    }

    init?(
        lineStart: CGPoint,
        lineEnd: CGPoint,
        widthMeters: Double,
        layout: ViewportLayout,
        viewportLength: CGFloat = 64.0
    ) {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let length = hypot(dx, dy)
        guard length > 1.0e-12 else {
            return nil
        }
        let midpoint = CGPoint(
            x: (lineStart.x + lineEnd.x) * 0.5,
            y: (lineStart.y + lineEnd.y) * 0.5
        )
        self.init(
            baseModelPoint: midpoint,
            modelDirection: CGPoint(x: -dy / length, y: dx / length),
            widthMeters: widthMeters,
            layout: layout,
            viewportLength: viewportLength
        )
    }

    func projectedTip(
        layout: ViewportLayout,
        widthMeters: Double? = nil
    ) -> CGPoint? {
        let width = max(widthMeters ?? baseWidthMeters, 1.0e-9)
        let lengthMeters = max(CGFloat(width) * 0.5, minimumLengthMeters)
        return layout.projectedPoint(
            CGPoint(
                x: baseModelPoint.x + modelDirection.x * lengthMeters,
                y: baseModelPoint.y + modelDirection.y * lengthMeters
            )
        )?.point
    }

    func slotWidth(
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> Double? {
        guard let projectedVector = projectedUnitVector(layout: layout),
              projectedVector.length > 1.0e-9 else {
            return nil
        }
        let direction = projectedVector.normalized
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let viewportDistance = delta.dx * direction.dx + delta.dy * direction.dy
        let modelDistance = Double(viewportDistance / projectedVector.length)
        return max(baseWidthMeters + modelDistance * 2.0, 1.0e-9)
    }

    private func projectedUnitVector(layout: ViewportLayout) -> CGVector? {
        guard let start = layout.projectedPoint(baseModelPoint)?.point,
              let end = layout.projectedPoint(
            CGPoint(
                x: baseModelPoint.x + modelDirection.x,
                y: baseModelPoint.y + modelDirection.y
            )
        )?.point else {
            return nil
        }
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private static func shouldFlipDirection(
        from point: CGPoint,
        direction: CGPoint,
        layout: ViewportLayout
    ) -> Bool? {
        guard let start = layout.projectedPoint(point)?.point,
              let end = layout.projectedPoint(
            CGPoint(
                x: point.x + direction.x,
                y: point.y + direction.y
            )
        )?.point else {
            return nil
        }
        let vector = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        if abs(vector.dx) > 1.0e-9 {
            return vector.dx < 0.0
        }
        return vector.dy > 0.0
    }

    private static func projectedLength(
        from point: CGPoint,
        direction: CGPoint,
        distance: CGFloat,
        layout: ViewportLayout
    ) -> CGFloat? {
        guard let start = layout.projectedPoint(point)?.point,
              let end = layout.projectedPoint(
            CGPoint(
                x: point.x + direction.x * distance,
                y: point.y + direction.y * distance
            )
        )?.point else {
            return nil
        }
        return hypot(end.x - start.x, end.y - start.y)
    }
}
