import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportSurfaceFrameAxisAffordanceGeometry: Equatable {
    var baseModelPoint: Point3D
    var modelDirection: Vector3D
    var minimumLengthMeters: Double

    init?(
        display: ViewportSurfaceFrameDisplay,
        axis: ViewportSurfaceFrameAxis,
        modelTransform: Transform3D,
        layout: ViewportLayout,
        viewportLength: CGFloat = 36.0
    ) {
        let localDirection = display.direction(for: axis)
        let transformedDirection = modelTransform.viewportTransformedVector(localDirection)
        guard transformedDirection.length > 1.0e-12 else {
            return nil
        }
        let basePoint = modelTransform.viewportTransformedPoint(display.position)
        let projectedUnitLength = Self.projectedLength(
            from: basePoint,
            direction: transformedDirection,
            distanceMeters: 1.0,
            layout: layout
        )
        guard projectedUnitLength > 1.0e-9 else {
            return nil
        }
        self.baseModelPoint = basePoint
        self.modelDirection = transformedDirection
        self.minimumLengthMeters = Double(viewportLength / projectedUnitLength)
    }

    func projectedTip(
        layout: ViewportLayout,
        distanceMeters: Double? = nil
    ) -> CGPoint {
        let distance = distanceMeters ?? minimumLengthMeters
        return layout.project(Self.offset(baseModelPoint, direction: modelDirection, distanceMeters: distance))
    }

    func dragDistance(
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

    private func projectedUnitVector(layout: ViewportLayout) -> CGVector {
        let start = layout.project(baseModelPoint)
        let end = layout.project(Self.offset(baseModelPoint, direction: modelDirection, distanceMeters: 1.0))
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private static func projectedLength(
        from point: Point3D,
        direction: Vector3D,
        distanceMeters: Double,
        layout: ViewportLayout
    ) -> CGFloat {
        let start = layout.project(point)
        let end = layout.project(offset(point, direction: direction, distanceMeters: distanceMeters))
        return hypot(end.x - start.x, end.y - start.y)
    }

    private static func offset(
        _ point: Point3D,
        direction: Vector3D,
        distanceMeters: Double
    ) -> Point3D {
        Point3D(
            x: point.x + direction.x * distanceMeters,
            y: point.y + direction.y * distanceMeters,
            z: point.z + direction.z * distanceMeters
        )
    }
}

private extension ViewportSurfaceFrameDisplay {
    func direction(for axis: ViewportSurfaceFrameAxis) -> Vector3D {
        switch axis {
        case .u:
            uAxis
        case .v:
            vAxis
        case .normal:
            normal
        }
    }
}
